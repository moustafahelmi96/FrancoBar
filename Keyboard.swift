import AppKit
import ApplicationServices

/// Synthesized ⌘C / ⌘V. Needs Accessibility permission.
enum Keyboard {
    private static var prompted = false

    static var trusted: Bool { AXIsProcessTrusted() }

    /// Returns false (and shows the system prompt once per launch) when Accessibility isn't granted.
    @discardableResult
    static func ensureTrusted() -> Bool {
        if trusted { return true }
        if !prompted {
            prompted = true
            AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        }
        return false
    }

    static func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    static func command(_ key: Int) {
        let src = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(key), keyDown: down)
            e?.flags = .maskCommand
            e?.post(tap: .cghidEventTap)
        }
    }

    /// Waits (up to 1s) until the user lets go of the shortcut's modifiers, so they don't mix into ⌘C/⌘V.
    static func whenModifiersReleased(_ block: @escaping () -> Void, deadline: Date = Date() + 1) {
        let held = CGEventSource.flagsState(.hidSystemState).intersection([.maskAlternate, .maskShift, .maskControl, .maskCommand])
        if held.isEmpty || Date() > deadline { return block() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { whenModifiersReleased(block, deadline: deadline) }
    }
}
