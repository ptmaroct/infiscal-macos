import AppKit

enum ClipboardService {
    /// Copies value to clipboard. Auto-clears after `clearAfter` seconds.
    static func copy(_ value: String, clearAfter: TimeInterval = 30) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)

        DispatchQueue.main.asyncAfter(deadline: .now() + clearAfter) {
            // Only clear if the clipboard still has our value
            if NSPasteboard.general.string(forType: .string) == value {
                NSPasteboard.general.clearContents()
            }
        }
    }
}
