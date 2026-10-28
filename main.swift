import AppKit
import Carbon.HIToolbox

// FrancoBar: a floating bar that turns Franco (Arabizi) into Arabic.
// ⌥Space toggles the bar, ⌥⇧Space converts selected text in any app (both changeable in Settings).

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let bar = BarController()
    lazy var settingsWindow = SettingsWindowController()
    var statusItem: NSStatusItem!
    let menu = NSMenu()
    let historyMenu = NSMenu()

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.mainMenu = editMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "ع"
        menu.delegate = self
        historyMenu.delegate = self
        statusItem.menu = menu
        Settings.shared.onShortcutsChanged = { [weak self] in self?.registerHotKeys() }
        registerHotKeys()
        bar.show()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        bar.show()
        return false
    }

    func registerHotKeys() {
        HotKeyCenter.shared.set([
            (Settings.shared.barShortcut, { [weak self] in self?.bar.toggle() }),
            (Settings.shared.selectionShortcut, { [weak self] in self?.convertSelection() }),
        ])
    }

    /// Copies the selection in the frontmost app, converts it, and pastes the Arabic over it.
    func convertSelection() {
        guard Keyboard.ensureTrusted() else { return }
        if bar.panel.isKeyWindow { bar.hide() }
        Keyboard.whenModifiersReleased {
            let pb = NSPasteboard.general
            let before = pb.changeCount
            Keyboard.command(kVK_ANSI_C)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                guard pb.changeCount != before, let text = pb.string(forType: .string),
                      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return NSSound.beep() }
                Transliterator.shared.convert(text) { c in
                    pb.clearContents()
                    pb.setString(c.text, forType: .string)
                    Settings.shared.addHistory(c.text)
                    Keyboard.command(kVK_ANSI_V)
                }
            }
        }
    }

    // MARK: menus

    func menuNeedsUpdate(_ m: NSMenu) {
        m.removeAllItems()
        if m === historyMenu {
            let history = Settings.shared.history
            if history.isEmpty { m.addItem(withTitle: "Nothing yet", action: nil, keyEquivalent: "") }
            for text in history {
                let flat = text.replacingOccurrences(of: "\n", with: " ")
                let title = flat.count > 50 ? String(flat.prefix(50)) + "…" : flat
                let item = m.addItem(withTitle: title, action: #selector(copyHistory(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = text
            }
            m.addItem(.separator())
            m.addItem(withTitle: "Clear History", action: #selector(clearHistory), keyEquivalent: "").target = self
            return
        }
        let s = Settings.shared
        add(m, "Show / Hide Bar   \(s.barShortcut.display)", #selector(toggleBar))
        add(m, "Convert Selected Text   \(s.selectionShortcut.display)", #selector(convertSelectionItem))
        let h = m.addItem(withTitle: "History", action: nil, keyEquivalent: "")
        h.submenu = historyMenu
        m.addItem(.separator())
        add(m, "Edit My Words…", #selector(editDictionary))
        add(m, "Settings…", #selector(openSettings), key: ",")
        add(m, "Open at Login", #selector(toggleLogin)).state = LoginItem.enabled ? .on : .off
        m.addItem(.separator())
        m.addItem(withTitle: "Quit FrancoBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @discardableResult
    private func add(_ m: NSMenu, _ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = m.addItem(withTitle: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc func toggleBar() { bar.toggle() }
    @objc func convertSelectionItem() { convertSelection() }
    @objc func openSettings() { settingsWindow.present() }
    @objc func toggleLogin() { LoginItem.set(!LoginItem.enabled) }
    @objc func clearHistory() { Settings.shared.clearHistory() }

    @objc func copyHistory(_ item: NSMenuItem) {
        guard let text = item.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc func editDictionary() {
        let t = Transliterator.shared
        t.reloadDictionary()
        NSWorkspace.shared.open([t.dictionaryURL], withApplicationAt: URL(fileURLWithPath: "/System/Applications/TextEdit.app"),
                                configuration: NSWorkspace.OpenConfiguration())
    }

    /// Accessory apps have no menu bar, so ⌘C/⌘V/⌘A in the text field need this.
    private func editMenu() -> NSMenu {
        let main = NSMenu()
        let item = main.addItem(withTitle: "Edit", action: nil, keyEquivalent: "")
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        item.submenu = edit
        return main
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
