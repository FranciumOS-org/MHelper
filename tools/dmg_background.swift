// SPDX-License-Identifier: GPL-2.0
// Draws the DMG window background: app → Applications arrow, and a row for
// the kext. Usage: swift tools/dmg_background.swift out.png out@2x.png
import AppKit

let W: CGFloat = 640, H: CGFloat = 420

func draw(scale: CGFloat, to path: String) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: W, height: H)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Light background with a soft top-to-bottom gradient
    NSGradient(starting: NSColor(white: 0.98, alpha: 1), ending: NSColor(white: 0.92, alpha: 1))!
        .draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -90)

    // Finder icon centres (top-left origin): app (170, 150), Applications (470, 150)
    // In AppKit's bottom-left coordinates the top row is at y = H - 150.
    let y = H - 150
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 255, y: y))
    arrow.line(to: NSPoint(x: 375, y: y))
    arrow.lineWidth = 6
    arrow.lineCapStyle = .round
    NSColor(white: 0.55, alpha: 1).setStroke()
    arrow.stroke()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: 390, y: y))
    head.line(to: NSPoint(x: 368, y: y + 16))
    head.line(to: NSPoint(x: 368, y: y - 16))
    head.close()
    NSColor(white: 0.55, alpha: 1).setFill()
    head.fill()

    func text(_ s: String, _ size: CGFloat, _ weight: NSFont.Weight, _ color: NSColor, centerX: CGFloat, topY: CGFloat) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
            .paragraphStyle: style,
        ]
        let str = NSAttributedString(string: s, attributes: attrs)
        let h = str.size().height
        str.draw(in: NSRect(x: centerX - 200, y: H - topY - h, width: 400, height: h))
    }

    text("Drag MHelper to Applications", 15, .semibold, NSColor(white: 0.25, alpha: 1), centerX: W / 2, topY: 38)

    // Divider and the kext row
    let line = NSBezierPath()
    line.move(to: NSPoint(x: 40, y: H - 262))
    line.line(to: NSPoint(x: W - 40, y: H - 262))
    line.lineWidth = 1
    NSColor(white: 0.80, alpha: 1).setStroke()
    line.stroke()
    text("Copy MHelper.kext to EFI/OC/Kexts, add it to config.plist and reboot",
         12, .regular, NSColor(white: 0.40, alpha: 1), centerX: W / 2, topY: 274)

    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

let args = CommandLine.arguments
draw(scale: 1, to: args[1])
draw(scale: 2, to: args[2])
