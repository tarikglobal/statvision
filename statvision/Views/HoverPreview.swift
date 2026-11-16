import SwiftUI

struct HoverPreview: View {
    @ObservedObject var store: MonitoringStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                EyeMark().frame(width: 29, height: 18)
                Text("statvision").font(.system(size: 12, weight: .heavy, design: .rounded))
                Spacer()
                Circle().fill(StatvisionPalette.accent(scheme)).frame(width: 5, height: 5)
                Text("CANLI").font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(1)
            }
            HStack(spacing: 8) {
                tile("CPU", value: store.cpuText, color: StatvisionPalette.accent(scheme))
                tile("RAM", value: store.memoryText, color: StatvisionPalette.cyan(scheme))
            }
            HStack(spacing: 8) {
                tile("SICAKLIK", value: store.latest?.temperature?.text ?? "— °C", color: .orange)
                tile("GÜÇ", value: store.latest?.power?.text ?? "— W", color: StatvisionPalette.accent(scheme))
            }
            Text("Ayrıntılar için göze tıkla.").font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 286)
        .background {
            ZStack {
                if !reduceTransparency { PreviewGlass() }
                StatvisionPalette.background(scheme).opacity(reduceTransparency ? 1 : 0.55)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(Color.primary.opacity(0.13)))
        .preferredColorScheme(store.appearance.colorScheme)
    }

    private func tile(_ title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(1.4).foregroundStyle(.secondary)
            Text(value).font(.system(size: 22, weight: .semibold, design: .rounded))
                .monospacedDigit().foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}
