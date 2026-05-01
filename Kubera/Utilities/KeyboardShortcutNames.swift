import Carbon
import AppKit

/// Manages a global keyboard shortcut using Carbon Hot Key API.
/// Default: Cmd+Shift+K to toggle the menubar menu.
final class GlobalShortcutManager {
    static let shared = GlobalShortcutManager()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var handler: (() -> Void)?
    private var currentKeyCode: UInt32 = 0
    private var currentModifiers: UInt32 = 0

    private init() {}

    /// Register a global hotkey. Default: Cmd+Shift+K
    func register(keyCode: UInt32 = UInt32(kVK_ANSI_K),
                  modifiers: UInt32 = UInt32(cmdKey | shiftKey),
                  handler: @escaping () -> Void) {
        self.handler = handler
        self.currentKeyCode = keyCode
        self.currentModifiers = modifiers

        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x494E4653) // "INFS"
        hotKeyID.id = 1

        // Install event handler (only once)
        if eventHandlerRef == nil {
            var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                           eventKind: UInt32(kEventHotKeyPressed))

            InstallEventHandler(
                GetApplicationEventTarget(),
                { (_, event, userData) -> OSStatus in
                    guard let userData else { return OSStatus(eventNotHandledErr) }
                    let mgr = Unmanaged<GlobalShortcutManager>.fromOpaque(userData).takeUnretainedValue()
                    mgr.handler?()
                    return noErr
                },
                1,
                &eventType,
                Unmanaged.passUnretained(self).toOpaque(),
                &eventHandlerRef
            )
        }

        RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                           GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    /// Update the shortcut to a new key combo, keeping the existing handler
    func updateShortcut(keyCode: UInt32, modifiers: UInt32) {
        guard let existingHandler = handler else { return }
        unregister()
        register(keyCode: keyCode, modifiers: modifiers, handler: existingHandler)
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    /// Check if a key combo conflicts with an already-registered global hotkey.
    /// Returns nil if no conflict, or a description string if conflict detected.
    func checkConflict(keyCode: UInt32, modifiers: UInt32) -> String? {
        // If it's our current shortcut, no conflict
        if keyCode == currentKeyCode && modifiers == currentModifiers {
            return nil
        }

        // Temporarily unregister our hotkey so we can test the new one
        let hadExisting = hotKeyRef != nil
        if hadExisting {
            unregister()
        }

        // Try to register the candidate hotkey
        var testRef: EventHotKeyRef?
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x54455354) // "TEST"
        hotKeyID.id = 99

        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                          GetApplicationEventTarget(), 0, &testRef)

        // Clean up test registration
        if let ref = testRef {
            UnregisterEventHotKey(ref)
        }

        // Re-register our original hotkey
        if hadExisting, let existingHandler = handler {
            register(keyCode: currentKeyCode, modifiers: currentModifiers, handler: existingHandler)
        }

        // Check result
        if status != noErr {
            let shortcutStr = ShortcutHelper.displayString(keyCode: keyCode, modifiers: modifiers)
            return "\(shortcutStr) is already in use by another application"
        }

        return nil
    }
}
