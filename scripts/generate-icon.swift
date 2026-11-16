// Compile with EyeArtwork.swift using scripts/generate-icon.sh.
import AppKit
import Foundation

@main
struct GenerateStatvisionIcon {
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let iconset = root.appendingPathComponent("build/AppIcon.iconset", isDirectory: true)
        try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        for logicalSize in [16, 32, 128, 256, 512] {
            try render(size: logicalSize, to: iconset.appendingPathComponent("icon_\(logicalSize)x\(logicalSize).png"))
            try render(size: logicalSize * 2, to: iconset.appendingPathComponent("icon_\(logicalSize)x\(logicalSize)@2x.png"))
        }
        print(iconset.path)
    }

    static func render(size: Int, to url: URL) throws {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw NSError(domain: "statvision.icon", code: 1)
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
        EyeArtwork.drawAppIcon(in: context.cgContext)
        NSGraphicsContext.restoreGraphicsState()
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "statvision.icon", code: 2)
        }
        try png.write(to: url)
    }
}
