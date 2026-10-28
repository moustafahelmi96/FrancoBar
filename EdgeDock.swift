import AppKit

/// Drag the bar against a screen edge and it tucks away into a small tab on that edge.
/// Clicking the tab (or any bar shortcut) brings it back next to the edge; dragging it away undocks it.
final class EdgeDock: NSObject, NSWindowDelegate {
    enum Edge { case left, right, top, bottom }

    var onTuck: () -> Void = {}
    var onTabClick: () -> Void = {}

    private let panel: NSPanel
    private let tab = TabPanel()
    private var edge: Edge?
    private var screen: NSScreen?
    private var dragging = false

    init(panel: NSPanel) {
        self.panel = panel
        super.init()
        panel.delegate = self
        tab.tabView.onClick = { [weak self] in self?.onTabClick() }
    }

    /// Call before the bar is shown: puts it back beside the edge it was tucked into.
    func barWillShow() {
        tab.orderOut(nil)
        guard let edge, let v = screen?.visibleFrame else { return }
        var f = panel.frame
        let inset: CGFloat = 8
        switch edge {
        case .left: f.origin.x = v.minX + inset
        case .right: f.origin.x = v.maxX - f.width - inset
        case .top: f.origin.y = v.maxY - f.height - inset
        case .bottom: f.origin.y = v.minY + inset
        }
        f.origin.x = min(max(f.origin.x, v.minX + inset), v.maxX - f.width - inset)
        f.origin.y = min(max(f.origin.y, v.minY + inset), v.maxY - f.height - inset)
        panel.setFrame(f, display: false)
    }

    /// Call after the bar is hidden: shows the tab while the bar is docked.
    func barDidHide() {
        guard let edge, let screen else { return }
        tab.show(on: edge, of: screen, along: panel.frame)
    }

    // Only user drags count (mouse held), so the bar resizing itself never docks or undocks it.
    func windowWillMove(_ n: Notification) { startDrag() }
    func windowDidMove(_ n: Notification) {
        if NSEvent.pressedMouseButtons & 1 != 0 { startDrag() }
    }

    private func startDrag() {
        guard !dragging else { return }
        dragging = true
        waitForMouseUp()
    }

    private func waitForMouseUp() {
        if NSEvent.pressedMouseButtons & 1 != 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.waitForMouseUp() }
            return
        }
        dragging = false
        if let (e, s) = edgeHit() {
            edge = e
            screen = s
            onTuck()
        } else {
            edge = nil
        }
    }

    /// Which outer screen edge the bar was pushed past, if any (edges shared with another display don't count).
    private func edgeHit() -> (Edge, NSScreen)? {
        let f = panel.frame
        guard let s = NSScreen.screens.max(by: { overlap($0.frame, f) < overlap($1.frame, f) }) else { return nil }
        let full = s.frame, vis = s.visibleFrame
        let outer: (NSPoint) -> Bool = { p in !NSScreen.screens.contains { $0.frame.contains(p) } }
        if f.minX < full.minX - 10, outer(NSPoint(x: full.minX - 1, y: f.midY)) { return (.left, s) }
        if f.maxX > full.maxX + 10, outer(NSPoint(x: full.maxX + 1, y: f.midY)) { return (.right, s) }
        if f.minY < vis.minY - 10, outer(NSPoint(x: f.midX, y: full.minY - 1)) { return (.bottom, s) }
        if f.maxY >= vis.maxY - 1, outer(NSPoint(x: f.midX, y: full.maxY + 1)) { return (.top, s) }
        return nil
    }

    private func overlap(_ a: NSRect, _ b: NSRect) -> CGFloat {
        let i = a.intersection(b)
        return i.isNull ? 0 : i.width * i.height
    }
}

/// The little tab left on the edge while the bar is tucked away.
final class TabPanel: NSPanel {
    let tabView = TabView()

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        contentView = tabView
    }

    func show(on edge: EdgeDock.Edge, of screen: NSScreen, along bar: NSRect) {
        let full = screen.frame, vis = screen.visibleFrame
        let long: CGFloat = 72, thick: CGFloat = 12
        var f: NSRect
        switch edge {
        case .left: f = NSRect(x: full.minX, y: bar.midY - long / 2, width: thick, height: long)
        case .right: f = NSRect(x: full.maxX - thick, y: bar.midY - long / 2, width: thick, height: long)
        case .top: f = NSRect(x: bar.midX - long / 2, y: vis.maxY - thick, width: long, height: thick)
        case .bottom: f = NSRect(x: bar.midX - long / 2, y: vis.minY, width: long, height: thick)
        }
        f.origin.x = min(max(f.origin.x, full.minX), full.maxX - f.width)
        f.origin.y = min(max(f.origin.y, vis.minY), vis.maxY - f.height)
        tabView.edge = edge
        setFrame(f, display: true)
        orderFrontRegardless()
    }
}

final class TabView: NSView {
    var onClick: () -> Void = {}
    var edge: EdgeDock.Edge = .right { didSet { needsDisplay = true } }
    private var hovering = false { didSet { needsDisplay = true } }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func draw(_ dirty: NSRect) {
        // Round only the side facing the screen: extend the shape past the edge it's stuck to.
        let r: CGFloat = 6
        var shape = bounds
        switch edge {
        case .left: shape.origin.x -= r; shape.size.width += r
        case .right: shape.size.width += r
        case .top: shape.size.height += r
        case .bottom: shape.origin.y -= r; shape.size.height += r
        }
        let vertical = edge == .left || edge == .right
        NSGraphicsContext.current?.cgContext.setAlpha(hovering ? 1 : 0.75)
        Brand.gradient.draw(in: NSBezierPath(roundedRect: shape, xRadius: r, yRadius: r), angle: vertical ? -90 : 0)
    }
}
