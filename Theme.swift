import AppKit

/// FrancoBar's colours, shared with the app icon (icon/make-icon.swift).
enum Brand {
    static let cyan = NSColor(srgbRed: 0x22 / 255.0, green: 0xD3 / 255.0, blue: 0xEE / 255.0, alpha: 1)
    static let violet = NSColor(srgbRed: 0x8B / 255.0, green: 0x5C / 255.0, blue: 0xF6 / 255.0, alpha: 1)
    static let pink = NSColor(srgbRed: 0xF4 / 255.0, green: 0x72 / 255.0, blue: 0xB6 / 255.0, alpha: 1)
    static let green = NSColor(srgbRed: 0x4A / 255.0, green: 0xDE / 255.0, blue: 0x80 / 255.0, alpha: 1)
    static var gradient: NSGradient { NSGradient(colors: [cyan, violet, pink])! }
}

/// A 1px cyan → violet → pink rule.
final class GradientLine: NSView {
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 1) }
    override func draw(_ dirty: NSRect) {
        Brand.gradient.draw(in: bounds, angle: 0)
    }
}

/// Capsule button for the alternative spellings: "⌘1 انهاردة".
final class Chip: NSButton {
    var isChosen = false { didSet { refresh() } }

    convenience init(key: Int, title: String, target: AnyObject, action: Selector) {
        self.init(frame: .zero)
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 10
        self.target = target
        self.action = action
        let s = NSMutableAttributedString(string: "⌘\(key) ", attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.45),
        ])
        s.append(NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]))
        attributedTitle = s
        refresh()
    }

    override var intrinsicContentSize: NSSize {
        let s = super.intrinsicContentSize
        return NSSize(width: s.width + 16, height: 20)
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    private func refresh() {
        layer?.backgroundColor = (isChosen ? Brand.violet.withAlphaComponent(0.75) : NSColor.white.withAlphaComponent(0.08)).cgColor
        layer?.borderWidth = isChosen ? 0 : 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
    }
}
