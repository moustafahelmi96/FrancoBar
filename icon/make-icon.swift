// Draws FrancoBar's app icon. Usage: swift icon/make-icon.swift icon/AppIcon.png
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments[1]

func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
let cyan = color(0x22D3EE), violet = color(0x8B5CF6), pink = color(0xF472B6)

let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
    let ctx = NSGraphicsContext.current!.cgContext
    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)

    // Drop shadow + dark background
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = .black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 28
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    NSGradient(colors: [color(0x1E1B4B), color(0x0B1022)])!.draw(in: squircle, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    squircle.addClip()
    // Soft glows
    NSGradient(colors: [violet.withAlphaComponent(0.55), violet.withAlphaComponent(0)])!
        .draw(fromCenter: NSPoint(x: 540, y: 470), radius: 0, toCenter: NSPoint(x: 540, y: 470), radius: 430, options: [])
    NSGradient(colors: [cyan.withAlphaComponent(0.30), cyan.withAlphaComponent(0)])!
        .draw(fromCenter: NSPoint(x: 230, y: 820), radius: 0, toCenter: NSPoint(x: 230, y: 820), radius: 380, options: [])
    // Top sheen
    NSGradient(colors: [.white.withAlphaComponent(0.10), .white.withAlphaComponent(0)])!
        .draw(in: NSRect(x: 100, y: 600, width: 824, height: 324), angle: -90)

    // Ghosted Franco "3" — the input
    let mono = NSFont.monospacedSystemFont(ofSize: 150, weight: .bold)
    NSAttributedString(string: "3", attributes: [.font: mono, .foregroundColor: NSColor.white.withAlphaComponent(0.22)])
        .draw(at: NSPoint(x: 200, y: 690))
    NSGraphicsContext.restoreGraphicsState()

    // Gradient ع — the output, centred on its ink (not its line box)
    let glyph = NSAttributedString(string: "ع", attributes: [.font: NSFont.systemFont(ofSize: 560, weight: .black), .foregroundColor: NSColor.white])
    let ink = glyph.boundingRect(with: .zero, options: [.usesDeviceMetrics, .usesLineFragmentOrigin])
    let gOrigin = NSPoint(x: tile.midX - ink.midX + 10, y: tile.midY - ink.midY - 30)
    let inkRect = ink.offsetBy(dx: gOrigin.x, dy: gOrigin.y)
    let letter = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
        glyph.draw(at: gOrigin)
        NSGraphicsContext.current!.compositingOperation = .sourceIn
        NSGradient(colors: [cyan, violet, pink])!.draw(in: inkRect.insetBy(dx: -40, dy: -40), angle: -60)
        return true
    }
    NSGraphicsContext.saveGraphicsState()
    squircle.addClip()
    let glow = NSShadow()
    glow.shadowColor = pink.withAlphaComponent(0.6)
    glow.shadowBlurRadius = 70
    glow.set()
    letter.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    ctx.flush()

    // Hairline edge
    NSColor.white.withAlphaComponent(0.12).setStroke()
    let edge = NSBezierPath(roundedRect: tile.insetBy(dx: 1.5, dy: 1.5), xRadius: 184, yRadius: 184)
    edge.lineWidth = 3
    edge.stroke()
    return true
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
