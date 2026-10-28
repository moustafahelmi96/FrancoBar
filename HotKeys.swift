import AppKit
import Carbon.HIToolbox

/// Global shortcuts via Carbon hot keys (no Accessibility permission needed).
final class HotKeyCenter {
    static let shared = HotKeyCenter()
    private var bindings: [(Shortcut, () -> Void)] = []
    private var refs: [EventHotKeyRef] = []

    private init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            DispatchQueue.main.async { HotKeyCenter.shared.fire(Int(id.id)) }
            return noErr
        }, 1, &spec, nil, nil)
    }

    func set(_ bindings: [(Shortcut, () -> Void)]) {
        self.bindings = bindings
        resume()
    }

    /// Used while recording a new shortcut so the current one can be pressed.
    func suspend() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs = []
    }

    func resume() {
        suspend()
        for (i, (s, _)) in bindings.enumerated() {
            var ref: EventHotKeyRef?
            RegisterEventHotKey(s.keyCode, s.modifiers, EventHotKeyID(signature: OSType(0x46424152), id: UInt32(i)),
                                GetApplicationEventTarget(), 0, &ref)
            if let ref { refs.append(ref) }
        }
    }

    private func fire(_ i: Int) {
        if bindings.indices.contains(i) { bindings[i].1() }
    }
}

/// Double-tap ⌘: press and release Command twice with nothing else in between.
/// Modifier-only taps can't be Carbon hot keys, so this watches flag changes (needs Accessibility).
final class DoubleCommandTap {
    private let action: () -> Void
    private var commandDown = false
    private var lastTap: TimeInterval = 0

    init(_ action: @escaping () -> Void) {
        self.action = action
        NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] in self?.handle($0) }
        NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] in self?.handle($0); return $0 }
    }

    private func handle(_ e: NSEvent) {
        let flags = e.modifierFlags.intersection([.command, .option, .control, .shift, .function])
        switch (e.type, flags) {
        case (.flagsChanged, .command):
            commandDown = true
        case (.flagsChanged, []) where commandDown:
            commandDown = false
            if e.timestamp - lastTap < 0.4 {
                lastTap = 0
                if Settings.shared.doubleCommand { action() }
            } else {
                lastTap = e.timestamp
            }
        default: // any key (⌘C…) or other modifier cancels the tap
            commandDown = false
            lastTap = 0
        }
    }
}
