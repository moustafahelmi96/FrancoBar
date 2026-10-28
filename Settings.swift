import AppKit
import Carbon.HIToolbox

struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32 // Carbon modifier mask
    var label: String

    var display: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + label
    }

    static func carbon(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        return m
    }
}

final class Settings {
    static let shared = Settings()
    private let d = UserDefaults.standard
    var onShortcutsChanged: () -> Void = {}

    var barShortcut: Shortcut {
        get { shortcut("barShortcut") ?? Shortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey), label: "Space") }
        set { d.set(try? JSONEncoder().encode(newValue), forKey: "barShortcut"); onShortcutsChanged() }
    }
    var selectionShortcut: Shortcut {
        get { shortcut("selectionShortcut") ?? Shortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey | shiftKey), label: "Space") }
        set { d.set(try? JSONEncoder().encode(newValue), forKey: "selectionShortcut"); onShortcutsChanged() }
    }
    var pauseDelay: Double {
        get { d.object(forKey: "pauseDelay") as? Double ?? 0.6 }
        set { d.set(newValue, forKey: "pauseDelay") }
    }
    var autoCopy: Bool {
        get { d.object(forKey: "autoCopy") as? Bool ?? true }
        set { d.set(newValue, forKey: "autoCopy") }
    }
    var doubleCommand: Bool {
        get { d.object(forKey: "doubleCommand") as? Bool ?? true }
        set { d.set(newValue, forKey: "doubleCommand") }
    }
    var pasteOnEnter: Bool {
        get { d.object(forKey: "pasteOnEnter") as? Bool ?? true }
        set { d.set(newValue, forKey: "pasteOnEnter") }
    }

    private(set) var history: [String] {
        get { d.stringArray(forKey: "history") ?? [] }
        set { d.set(newValue, forKey: "history") }
    }
    func addHistory(_ text: String) {
        history = Array(([text] + history.filter { $0 != text }).prefix(20))
    }
    func clearHistory() { history = [] }

    private func shortcut(_ key: String) -> Shortcut? {
        d.data(forKey: key).flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) }
    }
}
