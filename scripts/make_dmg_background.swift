import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("usage: make_dmg_background.swift <output.png>\n", stderr)
    exit(64)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let size = NSSize(width: 660, height: 420)
let image = NSImage(size: size)

func drawText(_ text: String, in rect: NSRect, size: CGFloat, weight: NSFont.Weight, color: NSColor, alignment: NSTextAlignment = .center) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = .byWordWrapping

    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
        .paragraphStyle: paragraph
    ]

    text.draw(in: rect, withAttributes: attributes)
}

func roundedRect(_ rect: NSRect, radius: CGFloat, fill: NSColor, stroke: NSColor? = nil) {
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    fill.setFill()
    path.fill()

    if let stroke {
        stroke.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

func drawArrow(from start: NSPoint, to end: NSPoint) {
    let path = NSBezierPath()
    path.move(to: start)
    path.curve(to: end, controlPoint1: NSPoint(x: start.x + 70, y: start.y + 38), controlPoint2: NSPoint(x: end.x - 70, y: end.y + 38))
    NSColor(calibratedRed: 0.18, green: 0.29, blue: 0.46, alpha: 0.88).setStroke()
    path.lineWidth = 6
    path.lineCapStyle = .round
    path.stroke()

    let head = NSBezierPath()
    head.move(to: end)
    head.line(to: NSPoint(x: end.x - 22, y: end.y + 15))
    head.move(to: end)
    head.line(to: NSPoint(x: end.x - 10, y: end.y + 25))
    head.lineWidth = 6
    head.lineCapStyle = .round
    head.stroke()
}

image.lockFocus()

let background = NSGradient(colors: [
    NSColor(calibratedRed: 0.94, green: 0.97, blue: 1.00, alpha: 1),
    NSColor(calibratedRed: 0.99, green: 0.98, blue: 0.94, alpha: 1)
])
background?.draw(in: NSRect(origin: .zero, size: size), angle: -24)

roundedRect(
    NSRect(x: 28, y: 28, width: 604, height: 364),
    radius: 28,
    fill: NSColor.white.withAlphaComponent(0.54),
    stroke: NSColor.white.withAlphaComponent(0.84)
)

drawText(
    "Install LyricBar",
    in: NSRect(x: 70, y: 318, width: 520, height: 38),
    size: 28,
    weight: .semibold,
    color: NSColor(calibratedRed: 0.11, green: 0.16, blue: 0.24, alpha: 1)
)

drawText(
    "Drag LyricBar to Applications",
    in: NSRect(x: 70, y: 286, width: 520, height: 28),
    size: 15,
    weight: .medium,
    color: NSColor(calibratedRed: 0.34, green: 0.39, blue: 0.47, alpha: 1)
)

drawArrow(from: NSPoint(x: 248, y: 178), to: NSPoint(x: 406, y: 178))

drawText(
    "LyricBar.app",
    in: NSRect(x: 104, y: 62, width: 150, height: 22),
    size: 13,
    weight: .medium,
    color: NSColor(calibratedRed: 0.22, green: 0.27, blue: 0.34, alpha: 1)
)

drawText(
    "Applications",
    in: NSRect(x: 408, y: 62, width: 150, height: 22),
    size: 13,
    weight: .medium,
    color: NSColor(calibratedRed: 0.22, green: 0.27, blue: 0.34, alpha: 1)
)

drawText(
    "Apple Music lyrics for your Touch Bar",
    in: NSRect(x: 70, y: 32, width: 520, height: 22),
    size: 12,
    weight: .regular,
    color: NSColor(calibratedRed: 0.45, green: 0.50, blue: 0.58, alpha: 1)
)

image.unlockFocus()

guard
    let tiffData = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiffData),
    let pngData = bitmap.representation(using: .png, properties: [:])
else {
    fputs("failed to render background\n", stderr)
    exit(1)
}

try pngData.write(to: outputURL)
