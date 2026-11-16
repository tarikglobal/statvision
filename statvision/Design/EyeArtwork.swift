import AppKit

/// A single vector mark is shared by the app icon, menu bar and SwiftUI views.
enum EyeArtwork {
    static func outline(in rect: CGRect, openness: CGFloat) -> CGPath {
        let amount = min(1, max(0.025, openness))
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width,
                    y: rect.minY + (0.5 + (y - 0.5) * amount) * rect.height)
        }
        let path = CGMutablePath()
        path.move(to: point(0.035, 0.52))
        path.addLine(to: point(0.24, 0.81))
        path.addLine(to: point(0.54, 0.70))
        path.addLine(to: point(0.965, 0.58))
        path.addLine(to: point(0.74, 0.23))
        path.addLine(to: point(0.40, 0.18))
        path.closeSubpath()
        return path
    }

    static func draw(in context: CGContext, rect: CGRect, openness: CGFloat = 1,
                     primary: CGColor, secondary: CGColor? = nil) {
        context.saveGState()
        context.setLineJoin(.round)
        context.setLineCap(.round)
        context.addPath(outline(in: rect, openness: openness))
        context.setStrokeColor(primary)
        context.setLineWidth(max(1.2, rect.width * 0.045))
        context.strokePath()
        if openness > 0.15 {
            context.addPath(outline(in: rect, openness: openness))
            context.clip()
            let iris = CGRect(x: rect.minX + rect.width * 0.365,
                              y: rect.minY + rect.height * (0.5 - 0.31 * openness),
                              width: rect.width * 0.27, height: rect.height * 0.62 * openness)
            context.setStrokeColor(secondary ?? primary)
            context.setLineWidth(max(1, rect.width * 0.025))
            context.strokeEllipse(in: iris)
            context.setFillColor(primary)
            context.fill(CGRect(x: rect.minX + rect.width * 0.474,
                                y: rect.minY + rect.height * (0.5 - 0.20 * openness),
                                width: rect.width * 0.052, height: rect.height * 0.40 * openness))
        }
        context.restoreGState()
    }

    static func statusColor(for load: EyeLoadLevel) -> NSColor {
        switch load {
        case .low: return NSColor(srgbRed: 0.10, green: 0.64, blue: 0.28, alpha: 1)
        case .moderate: return NSColor(srgbRed: 0.89, green: 0.40, blue: 0.02, alpha: 1)
        case .high, .overloaded: return NSColor(srgbRed: 0.95, green: 0.22, blue: 0.25, alpha: 1)
        case .unavailable: return NSColor(srgbRed: 0.55, green: 0.55, blue: 0.55, alpha: 1)
        }
    }

    static func drawTear(in context: CGContext, rect: CGRect) {
        let x = rect.minX + rect.width * 0.76
        let top = rect.minY + rect.height * 0.25
        let width = rect.width * 0.14
        let height = rect.height * 0.28
        let tear = CGMutablePath()
        tear.move(to: CGPoint(x: x, y: top))
        tear.addCurve(to: CGPoint(x: x, y: top - height),
                      control1: CGPoint(x: x + width, y: top - height * 0.65),
                      control2: CGPoint(x: x + width * 0.55, y: top - height))
        tear.addCurve(to: CGPoint(x: x, y: top),
                      control1: CGPoint(x: x - width * 0.55, y: top - height),
                      control2: CGPoint(x: x - width, y: top - height * 0.65))
        tear.closeSubpath()
        context.saveGState()
        context.addPath(tear)
        context.setFillColor(NSColor(srgbRed: 0.10, green: 0.72, blue: 0.95, alpha: 1).cgColor)
        context.fillPath()
        context.restoreGState()
    }

    static func statusImage(openness: CGFloat = 1, load: EyeLoadLevel? = nil) -> NSImage {
        let image = NSImage(size: NSSize(width: 27, height: 18), flipped: false) { bounds in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            draw(in: context, rect: bounds.insetBy(dx: 1, dy: 1), openness: openness,
                 primary: (load.map { statusColor(for: $0) } ?? .black).cgColor)
            if load == .overloaded { drawTear(in: context, rect: bounds.insetBy(dx: 1, dy: 1)) }
            return true
        }
        // Template images are recolored by macOS, which would erase load colors.
        image.isTemplate = load == nil
        image.accessibilityDescription = load.map { "statvision gözü · \($0.title)" } ?? "statvision gözü"
        return image
    }

    static func drawAppIcon(in context: CGContext) {
        let tile = CGPath(roundedRect: CGRect(x: 80, y: 80, width: 864, height: 864),
                          cornerWidth: 190, cornerHeight: 190, transform: nil)
        context.saveGState()
        context.addPath(tile)
        context.clip()
        let colors = [NSColor(srgbRed: 0.025, green: 0.045, blue: 0.075, alpha: 1).cgColor,
                      NSColor(srgbRed: 0.10, green: 0.14, blue: 0.18, alpha: 1).cgColor]
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray,
                                     locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: CGPoint(x: 200, y: 100),
                                       end: CGPoint(x: 900, y: 1000), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.045).cgColor)
        context.setLineWidth(2)
        for coordinate in stride(from: 144, through: 900, by: 96) {
            context.move(to: CGPoint(x: coordinate, y: 100))
            context.addLine(to: CGPoint(x: coordinate, y: 920))
            context.move(to: CGPoint(x: 100, y: coordinate))
            context.addLine(to: CGPoint(x: 920, y: coordinate))
        }
        context.strokePath()
        let lime = NSColor(srgbRed: 0.77, green: 1, blue: 0.23, alpha: 1).cgColor
        let cyan = NSColor(srgbRed: 0.21, green: 0.90, blue: 1, alpha: 1).cgColor
        // A sharp brow and telemetry bars give the eye its monitor identity.
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.14).cgColor)
        context.setLineWidth(6)
        context.move(to: CGPoint(x: 195, y: 767))
        context.addLine(to: CGPoint(x: 325, y: 820))
        context.addLine(to: CGPoint(x: 830, y: 720))
        context.strokePath()
        draw(in: context, rect: CGRect(x: 170, y: 322, width: 684, height: 445),
             primary: lime, secondary: cyan)
        for (index, height) in [22, 38, 28, 74, 118, 87, 50, 100, 63, 34, 18].enumerated() {
            context.setFillColor(NSColor(srgbRed: 0.77, green: 1, blue: 0.23,
                                         alpha: index == 4 ? 0.9 : 0.25).cgColor)
            context.fill(CGRect(x: 232 + index * 52, y: 203, width: 24, height: height))
        }
        context.restoreGState()
        context.addPath(tile)
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.16).cgColor)
        context.setLineWidth(3)
        context.strokePath()
    }
}
