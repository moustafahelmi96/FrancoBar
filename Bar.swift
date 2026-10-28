import AppKit

final class Panel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// The floating bar: Franco in, Arabic out. Click an Arabic word (or ⌘1–⌘5 for the last one) to change it;
/// FrancoBar remembers that choice.
final class BarController: NSObject, NSTextFieldDelegate, NSTextViewDelegate {
    let panel = Panel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 100),
                      styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
                      backing: .buffered, defer: false)
    private let input = NSTextField()
    private let output = NSTextView()
    private let status = NSTextField(labelWithString: "")
    private let alternatives = NSStackView()
    private var outputHeight: NSLayoutConstraint!
    private var debounce: Timer?
    private var conversion: Conversion?
    private var requestID = 0
    private var previousApp: NSRunningApplication?
    private let t = Transliterator.shared
    private let hint = "↩ paste · esc hide · click a word to change it"

    override init() {
        super.init()
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        [.closeButton, .miniaturizeButton, .zoomButton].forEach { panel.standardWindowButton($0)?.isHidden = true }

        let bg = NSVisualEffectView()
        bg.material = .hudWindow
        bg.state = .active
        bg.blendingMode = .behindWindow
        panel.contentView = bg

        input.placeholderString = "ekteb franco… (e.g. ana 3ayz a5rog)"
        input.font = .systemFont(ofSize: 15)
        input.bezelStyle = .roundedBezel
        input.focusRingType = .none
        input.delegate = self

        output.isEditable = false
        output.isSelectable = true
        output.drawsBackground = false
        output.delegate = self
        output.textContainerInset = .zero
        output.textContainer?.lineFragmentPadding = 0
        output.textContainer?.widthTracksTextView = true
        output.isVerticallyResizable = false
        output.linkTextAttributes = [.foregroundColor: NSColor.labelColor, .cursor: NSCursor.pointingHand]

        status.font = .systemFont(ofSize: 10)
        status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingTail
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        alternatives.orientation = .horizontal
        alternatives.spacing = 2
        alternatives.setContentHuggingPriority(.required, for: .horizontal)

        let bottom = NSStackView(views: [status, alternatives])
        bottom.distribution = .fill
        let stack = NSStackView(views: [input, output, bottom])
        stack.orientation = .vertical
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 8, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        bg.addSubview(stack)

        outputHeight = output.heightAnchor.constraint(equalToConstant: 24)
        NSLayoutConstraint.activate([
            bg.widthAnchor.constraint(equalToConstant: 520),
            stack.topAnchor.constraint(equalTo: bg.topAnchor),
            stack.bottomAnchor.constraint(equalTo: bg.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: bg.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: bg.trailingAnchor),
            input.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -24),
            output.widthAnchor.constraint(equalTo: input.widthAnchor),
            bottom.widthAnchor.constraint(equalTo: input.widthAnchor),
            outputHeight,
        ])

        if let f = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: f.midX - 260, y: f.maxY - 160))
        }

        // ⌘1–⌘5 pick an alternative for the last word.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, e.window === self.panel,
                  e.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                  let n = Int(e.charactersIgnoringModifiers ?? ""), (1...5).contains(n) else { return e }
            if let i = self.lastWordWithAlternatives, let c = self.conversion, c.source == self.input.stringValue,
               n <= c.words[i].candidates.count {
                self.pick(word: i, candidate: n - 1)
            }
            return nil
        }
        render()
    }

    // MARK: show / hide

    func toggle() { panel.isVisible ? hide() : show() }

    func show() {
        if let app = NSWorkspace.shared.frontmostApplication, app != .current { previousApp = app }
        t.reloadDictionary()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(input)
        input.currentEditor()?.selectAll(nil)
    }

    func hide() {
        debounce?.invalidate()
        if let c = conversion, c.source == input.stringValue, !c.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Settings.shared.addHistory(c.text)
        }
        panel.orderOut(nil)
        // Only happens after our own alert/menu activated us; hand focus back.
        if NSApp.isActive { previousApp?.activate(options: []) }
    }

    // MARK: typing

    func controlTextDidChange(_ n: Notification) {
        debounce?.invalidate()
        status.stringValue = ""
        debounce = .scheduledTimer(withTimeInterval: Settings.shared.pauseDelay, repeats: false) { [weak self] _ in
            self?.update { c in
                guard let self, let c else { return }
                if Settings.shared.autoCopy { self.copy(c) } else { self.status.stringValue = "↩ to copy" }
            }
        }
    }

    func control(_ c: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        switch sel {
        case #selector(NSResponder.cancelOperation(_:)):
            hide()
        case #selector(NSResponder.insertNewline(_:)):
            finish()
        default:
            return false
        }
        return true
    }

    private func finish() {
        debounce?.invalidate()
        let done: (Conversion?) -> Void = { [weak self] c in
            guard let self else { return }
            guard let c else { return self.hide() }
            self.copy(c)
            self.hide()
            if Settings.shared.pasteOnEnter, Keyboard.ensureTrusted() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { Keyboard.command(9) } // kVK_ANSI_V
            }
        }
        if let c = conversion, c.source == input.stringValue { done(c) } else { update(then: done) }
    }

    private func update(then done: @escaping (Conversion?) -> Void) {
        let text = input.stringValue
        requestID += 1
        let id = requestID
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            conversion = nil
            render()
            return done(nil)
        }
        t.convert(text) { [weak self] c in
            guard let self, id == self.requestID else { return }
            self.conversion = c
            self.render()
            done(c)
        }
    }

    private func copy(_ c: Conversion) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(c.text, forType: .string)
        status.stringValue = c.offline ? "✓ copied · offline" : "✓ copied"
    }

    // MARK: output

    private var lastWordWithAlternatives: Int? {
        conversion?.words.lastIndex { $0.candidates.count > 1 }
    }

    private func render() {
        let font = NSFont.systemFont(ofSize: 19, weight: .medium)
        let para = NSMutableParagraphStyle()
        para.alignment = .right
        para.baseWritingDirection = .rightToLeft
        let s = NSMutableAttributedString()
        for (i, w) in (conversion?.words ?? []).enumerated() {
            s.append(NSAttributedString(string: w.leading, attributes: [.font: font]))
            var attrs: [NSAttributedString.Key: Any] = [.font: font]
            if !w.franco.isEmpty { attrs[.link] = "word:\(i)" }
            s.append(NSAttributedString(string: w.text, attributes: attrs))
        }
        s.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: s.length))
        output.textStorage?.setAttributedString(s)

        alternatives.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if let i = lastWordWithAlternatives, let w = conversion?.words[i] {
            for (n, cand) in w.candidates.prefix(5).enumerated() {
                let b = NSButton(title: "⌘\(n + 1) \(cand)", target: self, action: #selector(alternativeClicked(_:)))
                b.bezelStyle = .inline
                b.controlSize = .small
                b.font = .systemFont(ofSize: 11, weight: n == w.chosen ? .bold : .regular)
                b.tag = i * 10 + n
                alternatives.addArrangedSubview(b)
            }
        }
        if conversion == nil { status.stringValue = hint }
        fit()
    }

    /// Grows/shrinks the bar to fit the Arabic, keeping its top edge in place.
    private func fit() {
        guard let content = panel.contentView, let lm = output.layoutManager, let tc = output.textContainer else { return }
        content.layoutSubtreeIfNeeded()
        lm.ensureLayout(for: tc)
        outputHeight.constant = max(24, ceil(lm.usedRect(for: tc).height))
        content.layoutSubtreeIfNeeded()
        var f = panel.frame
        let top = f.maxY
        f.size.height = content.fittingSize.height
        f.origin.y = top - f.height
        panel.setFrame(f, display: true)
    }

    // MARK: changing a word

    @objc private func alternativeClicked(_ b: NSButton) { pick(word: b.tag / 10, candidate: b.tag % 10) }

    @objc private func menuPick(_ item: NSMenuItem) {
        guard let p = item.representedObject as? [Int] else { return }
        pick(word: p[0], candidate: p[1])
    }

    private func pick(word i: Int, candidate n: Int) {
        guard var c = conversion, c.words.indices.contains(i), c.words[i].candidates.indices.contains(n) else { return }
        c.words[i].chosen = n
        conversion = c
        render()
        if Settings.shared.autoCopy { copy(c) }
        if !t.remember(c.words[i].franco, as: c.words[i].arabic) { status.stringValue = "⚠︎ dictionary.json has an error — not saved" }
    }

    func textView(_ tv: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        guard let s = link as? String, s.hasPrefix("word:"), let i = Int(s.dropFirst(5)),
              let w = conversion?.words[i], let event = NSApp.currentEvent else { return false }
        let menu = NSMenu()
        for (n, cand) in w.candidates.enumerated() {
            let item = NSMenuItem(title: cand, action: #selector(menuPick(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = [i, n]
            item.state = n == w.chosen ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let own = NSMenuItem(title: "Type my own for “\(w.franco)”…", action: #selector(typeOwn(_:)), keyEquivalent: "")
        own.target = self
        own.tag = i
        menu.addItem(own)
        if t.dictionary[w.franco] != nil {
            let forget = NSMenuItem(title: "Forget my choice for “\(w.franco)”", action: #selector(forget(_:)), keyEquivalent: "")
            forget.target = self
            forget.tag = i
            menu.addItem(forget)
        }
        NSMenu.popUpContextMenu(menu, with: event, for: tv)
        return true
    }

    @objc private func typeOwn(_ item: NSMenuItem) {
        guard var c = conversion, c.words.indices.contains(item.tag) else { return }
        let i = item.tag
        let field = NSTextField(string: c.words[i].arabic)
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        field.alignment = .right
        field.baseWritingDirection = .rightToLeft
        let alert = NSAlert()
        alert.messageText = "Arabic for “\(c.words[i].franco)”"
        alert.informativeText = "FrancoBar will always use this from now on."
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        defer { panel.makeKeyAndOrderFront(nil); panel.makeFirstResponder(input) }
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let typed = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !typed.isEmpty else { return }
        c.words[i].candidates = [typed] + c.words[i].candidates.filter { $0 != typed }
        c.words[i].chosen = 0
        conversion = c
        render()
        if Settings.shared.autoCopy { copy(c) }
        if !t.remember(c.words[i].franco, as: typed) { status.stringValue = "⚠︎ dictionary.json has an error — not saved" }
    }

    @objc private func forget(_ item: NSMenuItem) {
        guard let w = conversion?.words[item.tag] else { return }
        t.forget(w.franco)
        update { [weak self] c in if let c, Settings.shared.autoCopy { self?.copy(c) } }
    }
}
