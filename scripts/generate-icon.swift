// Reproducible vector drawing; uses only macOS AppKit. No downloaded assets.
import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("build/AppIcon.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(size: Int, filename: String) throws {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "statvision.icon", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Cannot create icon drawing context"])
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)

    let tile = NSBezierPath(roundedRect: NSRect(x: 80, y: 80, width: 864, height: 864),
                            xRadius: 195, yRadius: 195)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
    shadow.shadowBlurRadius = 28
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor(calibratedRed: 0.07, green: 0.14, blue: 0.19, alpha: 1).setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Draw a deterministic gradient without dithering, keeping the icon small.
    NSGraphicsContext.saveGraphicsState()
    tile.addClip()
    for row in 80..<944 {
        let progress = CGFloat(row - 80) / 863
        NSColor(calibratedRed: 0.035 + 0.095 * progress,
                green: 0.09 + 0.20 * progress,
                blue: 0.15 + 0.21 * progress, alpha: 1).setFill()
        NSRect(x: 80, y: row, width: 864, height: 1).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    NSColor.white.withAlphaComponent(0.10).setStroke()
    tile.lineWidth = 2
    tile.stroke()

    // A quiet grid and a single clear signal remain legible at small icon sizes.
    NSColor.white.withAlphaComponent(0.065).setStroke()
    let grid = NSBezierPath()
    for y in [340, 500, 660] {
        grid.move(to: NSPoint(x: 210, y: y))
        grid.line(to: NSPoint(x: 814, y: y))
    }
    grid.lineWidth = 5
    grid.stroke()

    let signal = NSBezierPath()
    let points: [NSPoint] = [
        NSPoint(x: 210, y: 490), NSPoint(x: 330, y: 490),
        NSPoint(x: 410, y: 670), NSPoint(x: 510, y: 310),
        NSPoint(x: 610, y: 590), NSPoint(x: 675, y: 490), NSPoint(x: 814, y: 490)
    ]
    signal.move(to: points[0])
    points.dropFirst().forEach { signal.line(to: $0) }
    signal.lineWidth = 49
    signal.lineCapStyle = .round
    signal.lineJoinStyle = .round
    NSColor(calibratedRed: 0.31, green: 0.94, blue: 0.83, alpha: 1).setStroke()
    signal.stroke()

    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "statvision.icon", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "Cannot encode icon PNG"])
    }
    try png.write(to: iconset.appendingPathComponent(filename))
}

for logicalSize in [16, 32, 128, 256, 512] {
    try render(size: logicalSize, filename: "icon_\(logicalSize)x\(logicalSize).png")
    try render(size: logicalSize * 2, filename: "icon_\(logicalSize)x\(logicalSize)@2x.png")
}
print(iconset.path)

