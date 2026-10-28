import AppKit
import Carbon.HIToolbox
import ServiceManagement

enum LoginItem {
    static var enabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            let a = NSAlert(error: error)
            a.informativeText = "Move FrancoBar to Applications and try again.\n\n" + error.localizedDescription
            a.runModal()
        }
    }
}

/// Click, then press the new shortcut. Esc cancels.
final class ShortcutButton: NSButton {
    var shortcut: Shortcut { didSet { title = shortcut.display } }
    var onChange: (Shortcut) -> Void = { _ in }
    private var monitor: Any?

    init(_ s: Shortcut) {
        shortcut = s
        super.init(frame: .zero)
        bezelStyle = .rounded
        title = s.display
        target = self
        action = #selector(record)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func record() {
        guard monitor == nil else { return stop() }
        title = "Press shortcut…"
        HotKeyCenter.shared.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self else { return e }
            if e.keyCode == UInt16(kVK_Escape) { self.stop(); return nil }
            let flags = e.modifierFlags.intersection([.command, .option, .control, .shift])
            guard !flags.intersection([.command, .option, .control]).isEmpty else { NSSound.beep(); return nil }
            let label = e.keyCode == UInt16(kVK_Space) ? "Space" : (e.charactersIgnoringModifiers ?? "?").uppercased()
            self.shortcut = Shortcut(keyCode: UInt32(e.keyCode), modifiers: Shortcut.carbon(flags), label: label)
            self.stop()
            self.onChange(self.shortcut)
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        title = shortcut.display
        HotKeyCenter.shared.resume()
    }
}

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let settings = Settings.shared
    private let pauseLabel = NSTextField(labelWithString: "")
    private let login = NSButton(checkboxWithTitle: "Open FrancoBar when I log in", target: nil, action: nil)
    private let accessStatus = NSTextField(labelWithString: "")
    private let accessButton = NSButton(title: "Open Accessibility Settings", target: nil, action: nil)

    convenience init() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 300), styleMask: [.titled, .closable],
                         backing: .buffered, defer: false)
        w.title = "FrancoBar Settings"
        w.isReleasedWhenClosed = false
        self.init(window: w)
        w.delegate = self
        build()
    }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        refresh()
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowDidBecomeKey(_ n: Notification) { refresh() }

    private func build() {
        let bar = ShortcutButton(settings.barShortcut)
        bar.onChange = { [weak self] in self?.settings.barShortcut = $0 }
        let selection = ShortcutButton(settings.selectionShortcut)
        selection.onChange = { [weak self] in self?.settings.selectionShortcut = $0 }

        let pause = NSSlider(value: settings.pauseDelay, minValue: 0.3, maxValue: 2.0, target: self, action: #selector(pauseChanged(_:)))
        pause.widthAnchor.constraint(equalToConstant: 180).isActive = true
        let pauseRow = NSStackView(views: [pause, pauseLabel])

        let autoCopy = NSButton(checkboxWithTitle: "Copy automatically when I pause", target: self, action: #selector(autoCopyChanged(_:)))
        autoCopy.state = settings.autoCopy ? .on : .off
        let paste = NSButton(checkboxWithTitle: "Enter pastes into the app I was typing in", target: self, action: #selector(pasteChanged(_:)))
        paste.state = settings.pasteOnEnter ? .on : .off
        login.target = self
        login.action = #selector(loginChanged(_:))
        accessButton.target = self
        accessButton.action = #selector(openAccessibility)
        accessStatus.textColor = .secondaryLabelColor
        let accessRow = NSStackView(views: [accessStatus, accessButton])

        let grid = NSGridView(views: [
            [label("Show / hide bar:"), bar],
            [label("Convert selected text:"), selection],
            [label("Pause before copying:"), pauseRow],
            [NSGridCell.emptyContentView, autoCopy],
            [NSGridCell.emptyContentView, paste],
            [NSGridCell.emptyContentView, login],
            [label("Accessibility:"), accessRow],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        grid.rowSpacing = 12
        grid.columnSpacing = 10

        let note = NSTextField(wrappingLabelWithString:
            "Accessibility is needed for “Enter pastes” and “Convert selected text”. After rebuilding the app you may need to switch it off and on again there.")
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [grid, note])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            note.widthAnchor.constraint(equalToConstant: 420),
        ])
        window?.contentView = content
    }

    private func label(_ s: String) -> NSTextField { NSTextField(labelWithString: s) }

    private func refresh() {
        pauseLabel.stringValue = String(format: "%.1fs", settings.pauseDelay)
        login.state = LoginItem.enabled ? .on : .off
        accessStatus.stringValue = Keyboard.trusted ? "✓ Allowed" : "Not allowed"
        accessButton.isHidden = Keyboard.trusted
    }

    @objc private func pauseChanged(_ s: NSSlider) {
        settings.pauseDelay = (s.doubleValue * 10).rounded() / 10
        refresh()
    }
    @objc private func autoCopyChanged(_ b: NSButton) { settings.autoCopy = b.state == .on }
    @objc private func pasteChanged(_ b: NSButton) {
        settings.pasteOnEnter = b.state == .on
        if settings.pasteOnEnter { Keyboard.ensureTrusted() }
    }
    @objc private func loginChanged(_ b: NSButton) {
        LoginItem.set(b.state == .on)
        refresh()
    }
    @objc private func openAccessibility() {
        Keyboard.ensureTrusted()
        Keyboard.openAccessibilitySettings()
    }
}
