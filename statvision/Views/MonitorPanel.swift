import AppKit
import SwiftUI

struct MonitorPanel: View {
    @ObservedObject var store: MonitoringStore
    let openSettings: () -> Void
    let closePanel: () -> Void
    @State private var contentHeight: CGFloat = 680
    @Environment(\.colorScheme) private var scheme

    private var accent: Color { StatvisionPalette.accent(scheme) }
    private var cyan: Color { StatvisionPalette.cyan(scheme) }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView { panelContent }
                .frame(width: 360, height: min(contentHeight, max(260, (NSScreen.main?.visibleFrame.height ?? 830) - 112)))
            footer
        }
            .onPreferenceChange(PanelContentHeight.self) { height in
                if height > 0, abs(contentHeight - height) > 1 { contentHeight = height }
            }
            .background(MonitorBackdrop())
            .tint(accent)
            .preferredColorScheme(store.appearance.colorScheme)
            .onExitCommand(perform: closePanel)
    }

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                EyeMark().frame(width: 41, height: 29)
                    .padding(5)
                    .background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text("statvision").font(.system(size: 22, weight: .heavy, design: .rounded))
                    Text("GÖZÜN SİSTEMDE.").font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(1.7).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                HStack(spacing: 4) {
                    Circle().fill(accent).frame(width: 4, height: 4)
                    Text("\(store.refreshInterval) sn").font(.system(size: 10, weight: .semibold, design: .monospaced))
                }
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(accent.opacity(0.08), in: Capsule())
                .accessibilityLabel("Ölçüm aralığı \(store.refreshInterval) saniye")
            }

            HStack(spacing: 10) {
                metric(title: "CPU", value: store.cpuText, detail: "Toplam işlemci", symbol: "cpu", color: accent, size: 39)
                metric(title: "RAM", value: store.memoryText, detail: totalMemoryText, symbol: "memorychip", color: cyan, size: 29)
            }
            .accessibilityElement(children: .contain)

            VStack(spacing: 6) {
                HStack {
                    Text("RAM KULLANIMI").font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1)
                    Spacer()
                    Text(memoryPercentText).font(.caption.monospacedDigit().weight(.semibold))
                }
                .foregroundStyle(.secondary)
                ProgressView(value: store.latest?.memory?.percentage ?? 0, total: 100)
                    .tint(cyan)
                    .accessibilityLabel("RAM kullanımı").accessibilityValue(memoryPercentText)
                    .opacity(store.latest?.memory == nil ? 0.35 : 1)
            }
            pressureIndicator

            HStack(spacing: 10) {
                telemetry(title: "SICAKLIK", value: store.latest?.temperature?.text ?? "— °C",
                          detail: temperatureDetail, symbol: "thermometer.medium", color: .orange)
                    .help(store.latest?.temperature.map { "\($0.source.title) · \($0.sensorName). Kasa veya ortam sıcaklığı değildir." }
                          ?? "Desteklenen sıcaklık sensörü okunamadı.")
                telemetry(title: "GÜÇ", value: store.latest?.power?.text ?? "— W",
                          detail: powerDetail, symbol: "bolt.fill", color: accent)
                    .help("Mac’in son güç sensörü ölçümüdür; priz veya adaptör kapasitesi değildir. Sensör daha seyrek yenilenebilir.")
            }

            VStack(spacing: 12) {
                HistoryChart(title: "CPU", samples: chartSamples, end: chartEnd,
                             metric: .cpu, color: accent, currentPercentage: store.latest?.cpu.percentage)
                Rectangle().fill(Color.primary.opacity(0.065)).frame(height: 1)
                HistoryChart(title: "RAM", samples: chartSamples, end: chartEnd,
                             metric: .memory, color: cyan, currentPercentage: store.latest?.memory?.percentage)
            }
            .monitorCard()

            Text(statusExplanation).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            DisclosureGroup(isExpanded: $store.applicationsExpanded) {
                ApplicationUsageView(snapshot: store.applicationUsage, hasSample: store.hasApplicationSample,
                    disabledReason: store.terminationDisabledReason, closeApplication: store.closeApplication,
                    terminationMessage: store.terminationMessage)
                    .padding(.top, 10)
            } label: {
                Text("En çok tüketen 5 uygulama").font(.system(size: 11, weight: .semibold))
            }
            .monitorCard()
            .accessibilityHint("CPU ve RAM uygulama listesini açar veya kapatır")

        }
        .padding(16).frame(width: 360)
        .background(GeometryReader { geometry in
            Color.clear.preference(key: PanelContentHeight.self, value: geometry.size.height)
        })
    }

    private var footer: some View {
        HStack {
            Button(action: openSettings) { Label("Ayarlar", systemImage: "slider.horizontal.3") }
                .keyboardShortcut(",", modifiers: .command)
                .accessibilityHint("Göz modunu, menü çubuğunu ve görünümü ayarlar")
            Spacer()
            Button("Çıkış", action: { NSApplication.shared.terminate(nil) })
                .foregroundStyle(.secondary).keyboardShortcut("q", modifiers: .command)
        }
        .buttonStyle(.borderless).font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 19).padding(.vertical, 12)
        .overlay(alignment: .top) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1) }
    }

    private var chartEnd: TimeInterval { SampleClock.now }
    private var chartSamples: [SystemSample] { store.history.visible(at: chartEnd) }
    private var totalMemoryText: String {
        guard let memory = store.latest?.memory else { return "Ölçüm bekleniyor" }
        return "/ " + memory.totalGB.formatted(.number.precision(.fractionLength(1))) + " GB toplam"
    }
    private var memoryPercentText: String {
        store.latest?.memory.map { $0.percentage.formatted(.number.precision(.fractionLength(0))) + "%" } ?? "—"
    }
    private var temperatureDetail: String {
        guard let reading = store.latest?.temperature else { return "Veri alınamadı" }
        return reading.source == .chipHotspot ? "En sıcak çip sensörü" : "PMU sensörü"
    }
    private var powerDetail: String {
        guard let reading = store.latest?.power else { return "Veri alınamadı" }
        return reading.source == .systemLoad ? "Son sistem ölçümü" : "Pil deşarjı"
    }
    private var statusExplanation: String {
        guard let sample = store.latest else { return "Sistem ölçümleri hazırlanıyor…" }
        if sample.cpu.status != .valid { return sample.cpu.status.explanation }
        if sample.memory == nil { return "RAM istatistikleri okunamadı; yeniden denenecek." }
        return "SON 60 SANİYE · YEREL ÖLÇÜM"
    }

    private func metric(title: String, value: String, detail: String, symbol: String,
                        color: Color, size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label(title, systemImage: symbol).font(.system(size: 10, weight: .bold, design: .monospaced))
                Spacer()
                Rectangle().fill(color).frame(width: 18, height: 2)
            }
            .foregroundStyle(color)
            Text(value).font(.system(size: size, weight: .bold, design: .rounded))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
                .frame(height: 46, alignment: .bottomLeading)
            Text(detail).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading).monitorCard()
        .accessibilityElement(children: .ignore).accessibilityLabel(title)
        .accessibilityValue("\(value), \(detail)")
    }

    private func telemetry(title: String, value: String, detail: String, symbol: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: symbol).font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.8).foregroundStyle(.secondary)
            Text(value).font(.system(size: 23, weight: .semibold, design: .rounded))
                .foregroundStyle(color).monospacedDigit().lineLimit(1)
            Text(detail).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading).monitorCard()
        .accessibilityElement(children: .ignore).accessibilityLabel(title)
        .accessibilityValue("\(value), \(detail)")
    }

    private var pressureIndicator: some View {
        let pressure = store.latest?.pressure ?? .unavailable
        let source = store.latest?.pressureSource ?? .unavailable
        return HStack(spacing: 6) {
            Image(systemName: pressure.symbol).foregroundStyle(pressure.color).accessibilityHidden(true)
            Text("Bellek baskısı").foregroundStyle(.secondary)
            Spacer()
            Text(pressure.title).foregroundStyle(pressure.color).fontWeight(.semibold)
        }
        .font(.system(size: 10))
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(pressure.color.opacity(0.055), in: RoundedRectangle(cornerRadius: 7))
        .help(source.explanation)
        .accessibilityElement(children: .ignore).accessibilityLabel("Bellek baskısı")
        .accessibilityValue("\(pressure.title). \(source.explanation)")
    }
}

private struct PanelContentHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private extension MemoryPressure {
    var color: Color {
        switch self {
        case .normal: return .green
        case .warning: return .orange
        case .critical: return .red
        case .unavailable: return .secondary
        }
    }
    var symbol: String {
        switch self {
        case .normal: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "exclamationmark.octagon.fill"
        case .unavailable: return "questionmark.circle"
        }
    }
}
