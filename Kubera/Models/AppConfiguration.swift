import Foundation
import Carbon
import AppKit

struct AppConfiguration: Codable {
    var projectId: String
    var environment: String
    var secretPath: String
    var baseURL: String
    var projectName: String?
    var organizationId: String?

    // Keyboard shortcut (nil = use defaults: Cmd+Shift+K)
    var shortcutKeyCode: UInt32?
    var shortcutModifiers: UInt32?

    static let defaultBaseURL = "https://app.infisical.com"
    static let defaultEnvironment = "dev"
    static let defaultSecretPath = "/"
    static let defaultShortcutKeyCode = UInt32(kVK_ANSI_K)
    static let defaultShortcutModifiers = UInt32(cmdKey | shiftKey)

    private static let userDefaultsKey = "infisical_app_config"

    /// Get the configured or default shortcut key code
    var resolvedKeyCode: UInt32 {
        shortcutKeyCode ?? Self.defaultShortcutKeyCode
    }

    /// Get the configured or default shortcut modifiers
    var resolvedModifiers: UInt32 {
        shortcutModifiers ?? Self.defaultShortcutModifiers
    }

    /// Human-readable shortcut string (e.g., "⌘ ⇧ K")
    var shortcutDisplayString: String {
        ShortcutHelper.displayString(keyCode: resolvedKeyCode, modifiers: resolvedModifiers)
    }

    /// Direct link to the project secrets page on Infisical dashboard
    var dashboardURL: String {
        if let orgId = organizationId {
            return "\(baseURL)/organizations/\(orgId)/projects/secret-management/\(projectId)/overview"
        }
        return baseURL
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
        }
    }

    static func load() -> AppConfiguration? {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            return nil
        }
        return try? JSONDecoder().decode(AppConfiguration.self, from: data)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }
}

// MARK: - Shortcut Helper

enum ShortcutHelper {
    /// Convert modifier flags to display symbols
    static func modifierSymbols(for modifiers: UInt32) -> String {
        var symbols = ""
        if modifiers & UInt32(controlKey) != 0 { symbols += "⌃ " }
        if modifiers & UInt32(optionKey) != 0 { symbols += "⌥ " }
        if modifiers & UInt32(shiftKey) != 0 { symbols += "⇧ " }
        if modifiers & UInt32(cmdKey) != 0 { symbols += "⌘ " }
        return symbols
    }

    /// Convert a Carbon key code to a display string
    static func keyName(for keyCode: UInt32) -> String {
        let keyMap: [UInt32: String] = [
            UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
            UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
            UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
            UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
            UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
            UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
            UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
            UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
            UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
            UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
            UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
            UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
            UInt32(kVK_ANSI_9): "9",
            UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3",
            UInt32(kVK_F4): "F4", UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6",
            UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8", UInt32(kVK_F9): "F9",
            UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
            UInt32(kVK_Space): "Space", UInt32(kVK_Return): "Return",
            UInt32(kVK_Tab): "Tab", UInt32(kVK_Escape): "Esc",
            UInt32(kVK_Delete): "Delete",
            UInt32(kVK_ANSI_Minus): "-", UInt32(kVK_ANSI_Equal): "=",
            UInt32(kVK_ANSI_LeftBracket): "[", UInt32(kVK_ANSI_RightBracket): "]",
            UInt32(kVK_ANSI_Semicolon): ";", UInt32(kVK_ANSI_Quote): "'",
            UInt32(kVK_ANSI_Comma): ",", UInt32(kVK_ANSI_Period): ".",
            UInt32(kVK_ANSI_Slash): "/", UInt32(kVK_ANSI_Backslash): "\\",
            UInt32(kVK_ANSI_Grave): "`",
        ]
        return keyMap[keyCode] ?? "?"
    }

    /// Full display string combining modifiers + key
    static func displayString(keyCode: UInt32, modifiers: UInt32) -> String {
        modifierSymbols(for: modifiers) + keyName(for: keyCode)
    }

    /// Convert NSEvent modifier flags to Carbon modifier flags
    static func carbonModifiers(from nsFlags: NSEvent.ModifierFlags) -> UInt32 {
        var carbonMods: UInt32 = 0
        if nsFlags.contains(.command) { carbonMods |= UInt32(cmdKey) }
        if nsFlags.contains(.shift) { carbonMods |= UInt32(shiftKey) }
        if nsFlags.contains(.option) { carbonMods |= UInt32(optionKey) }
        if nsFlags.contains(.control) { carbonMods |= UInt32(controlKey) }
        return carbonMods
    }
}
