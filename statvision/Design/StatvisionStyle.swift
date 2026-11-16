import AppKit
import SwiftUI

enum StatvisionPalette {
    static func accent(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.77, green: 1, blue: 0.23) : Color(red: 0.21, green: 0.40, blue: 0.04)
    }
    static func cyan(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.21, green: 0.90, blue: 1) : Color(red: 0, green: 0.40, blue: 0.55)
    }
    static func background(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.035, green: 0.055, blue: 0.08) : Color(red: 0.94, green: 0.96, blue: 0.98)
    }
}

struct EyeMark: View {
    var load: EyeLoadLevel? = nil
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Canvas { context, size in
            context.withCGContext { cg in
                cg.translateBy(x: 0, y: size.height)
                cg.scaleBy(x: 1, y: -1)
                EyeArtwork.draw(in: cg, rect: CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 1),
                    primary: (load.map { EyeArtwork.statusColor(for: $0) }
                        ?? NSColor(StatvisionPalette.accent(scheme))).cgColor,
                    secondary: (load.map { EyeArtwork.statusColor(for: $0) }
                        ?? NSColor(StatvisionPalette.cyan(scheme))).cgColor)
                if load == .overloaded {
                    EyeArtwork.drawTear(in: cg, rect: CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 1))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

struct MonitorBackdrop: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        LinearGradient(colors: [StatvisionPalette.background(scheme),
                                scheme == .dark ? Color(red: 0.075, green: 0.10, blue: 0.13) : .white],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

private struct MonitorCard: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content.padding(12)
            .background(scheme == .dark ? Color.white.opacity(0.035) : Color.white.opacity(0.9),
                        in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.075), lineWidth: 1))
    }
}

extension View {
    func monitorCard() -> some View { modifier(MonitorCard()) }
}

struct PreviewGlass: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) { }
}
