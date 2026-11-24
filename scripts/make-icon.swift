// Renders the app icon into LarkBar/Resources/Assets.xcassets/AppIcon.appiconset.
// Usage: swift scripts/make-icon.swift
import AppKit

let output = URL(fileURLWithPath: "LarkBar/Resources/Assets.xcassets/AppIcon.appiconset")

func render(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(size)
    // macOS icon grid: 824/1024 body with a continuous-corner squircle.
    let inset = s * 100 / 1024
    let body = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let path = NSBezierPath(roundedRect: body, xRadius: body.width * 0.225, yRadius: body.width * 0.225)
    NSGradient(colors: [NSColor(red: 0.16, green: 0.17, blue: 0.20, alpha: 1),
                        NSColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1)])!
        .draw(in: path, angle: -90)

    // A microphone drawn from plain shapes. (SF Symbols' license doesn't allow them in app icons.)
    NSColor(red: 1.0, green: 0.62, blue: 0.20, alpha: 1).setFill()
    NSColor(red: 1.0, green: 0.62, blue: 0.20, alpha: 1).setStroke()
    let u = s / 1024
    let capsule = NSRect(x: 512 * u - 92 * u, y: 452 * u, width: 184 * u, height: 312 * u)
    NSBezierPath(roundedRect: capsule, xRadius: 92 * u, yRadius: 92 * u).fill()
    let holder = NSBezierPath()
    holder.appendArc(withCenter: NSPoint(x: 512 * u, y: 560 * u), radius: 152 * u, startAngle: 180, endAngle: 360, clockwise: false)
    holder.lineWidth = 40 * u
    holder.lineCapStyle = .round
    holder.stroke()
    let stand = NSBezierPath()
    stand.move(to: NSPoint(x: 512 * u, y: 408 * u))
    stand.line(to: NSPoint(x: 512 * u, y: 300 * u))
    stand.move(to: NSPoint(x: 420 * u, y: 290 * u))
    stand.line(to: NSPoint(x: 604 * u, y: 290 * u))
    stand.lineWidth = 40 * u
    stand.lineCapStyle = .round
    stand.stroke()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try! render(size: points * scale).write(to: output.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try! JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: output.appendingPathComponent("Contents.json"))
print("Wrote \(images.count) icon sizes")
