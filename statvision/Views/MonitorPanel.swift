import AppKit
import SwiftUI

struct MonitorPanel: View {
    @ObservedObject var store: MonitoringStore
    let openSettings: () -> Void
    let closePanel: () -> Void
    @State private var contentHeight: CGFloat = 600

    var body: some View {
        ScrollView {
            panelContent
        }
        .frame(width: 336, height: min(contentHeight, max(300, (NSScreen.main?.visibleFrame.height ?? 830) - 70)))
        .onPreferenceChange(PanelContentHeight.self) { height in
            if height > 0, abs(contentHeight - height) > 1 { contentHeight = height }
        }
        .background(.regularMaterial)
        .tint(.teal)
        .preferredColorScheme(store.appearance.colorScheme)
        .onExitCommand(perform: closePanel)
    }

    private var panelContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 32, height: 32)
                    .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("statvision").font(.headline)
                    Text("Sistemine küçük bir bakış").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(store.refreshInterval) sn")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .help("Ölçüm yenileme aralığı")
            }
            Divider()
            HStack(alignment: .top, spacing: 16) {
                metric(title: "CPU", value: store.cpuText, detail: "Toplam kullanım", symbol: "cpu")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Divider().frame(height: 64)
                metric(title: "RAM", value: store.memoryText, detail: totalMemoryText, symbol: "memorychip")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .contain)

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("RAM kullanımı").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(memoryPercentText).font(.caption.monospacedDigit().weight(.medium))
                }
                ProgressView(value: store.latest?.memory?.percentage ?? 0, total: 100)
                    .tint(.teal)
                    .accessibilityLabel("RAM kullanımı")
                    .accessibilityValue(memoryPercentText)
                    .opacity(store.latest?.memory == nil ? 0.35 : 1)
            }
            pressureIndicator
            temperatureIndicator
            powerIndicator
            Divider()
            VStack(spacing: 12) {
                HistoryChart(title: "CPU", samples: chartSamples, end: chartEnd,
                             metric: .cpu, color: .blue,
                             currentPercentage: store.latest?.cpu.percentage)
                HistoryChart(title: "RAM", samples: chartSamples, end: chartEnd,
                             metric: .memory, color: .teal,
                             currentPercentage: store.latest?.memory?.percentage)
            }
            Text(statusExplanation)
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            DisclosureGroup(isExpanded: $store.applicationsExpanded) {
                ApplicationUsageView(snapshot: store.applicationUsage,
                                     hasSample: store.hasApplicationSample,
                                     disabledReason: store.terminationDisabledReason,
                                     closeApplication: store.closeApplication,
                                     terminationMessage: store.terminationMessage)
                    .padding(.top, 8)
            } label: {
                Text("En çok tüketen 5 uygulama").font(.caption.weight(.semibold))
            }
            .accessibilityHint("CPU ve RAM uygulama listesini açar veya kapatır")
            Divider()
            HStack {
                Button(action: openSettings) { Label("Ayarlar", systemImage: "gearshape") }
                    .keyboardShortcut(",", modifiers: .command)
                    .accessibilityHint("Menü çubuğu göstergelerini, yenileme aralığını ve görünümü değiştirir")
                Spacer()
                Button("Çıkış", action: { NSApplication.shared.terminate(nil) })
                    .keyboardShortcut("q", modifiers: .command)
            }
            .buttonStyle(.borderless)
            .font(.callout)
        }
        .padding(16)
        .frame(width: 336)
        .background(GeometryReader { geometry in
            Color.clear.preference(key: PanelContentHeight.self, value: geometry.size.height)
        })
    }

    private var chartEnd: TimeInterval { SampleClock.now }
    private var chartSamples: [SystemSample] { store.history.visible(at: chartEnd) }
    private var totalMemoryText: String {
        guard let memory = store.latest?.memory else { return "Ölçüm bekleniyor" }
        return "/ " + memory.totalGB.formatted(.number.precision(.fractionLength(1))) + " GB toplam"
    }
    private var memoryPercentText: String {
        guard let memory = store.latest?.memory else { return "Kullanılamıyor" }
        return memory.percentage.formatted(.number.precision(.fractionLength(0))) + "%"
    }
    private var statusExplanation: String {
        guard let sample = store.latest else { return "Sistem ölçümleri hazırlanıyor…" }
        if sample.cpu.status != .valid { return sample.cpu.status.explanation }
        if sample.memory == nil { return "RAM istatistikleri okunamadı; yeniden denenecek." }
        return "Son 60 saniye"
    }

    private func metric(title: String, value: String, detail: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 25, weight: .semibold, design: .rounded))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
            Text(detail).font(.caption2).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(value), \(detail)")
    }

    private var pressureIndicator: some View {
        let pressure = store.latest?.pressure ?? .unavailable
        let origin = store.latest?.pressureSource ?? .unavailable
        return HStack(alignment: .top, spacing: 9) {
            Image(systemName: pressure.symbol)
                .foregroundStyle(pressure.color).font(.system(size: 13, weight: .semibold))
                .padding(.top, 2).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("Bellek baskısı").font(.caption.weight(.medium))
                    Spacer()
                    Text(pressure.title).font(.caption.weight(.semibold)).foregroundStyle(pressure.color)
                }
                Text(origin.explanation).font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Bellek baskısı")
        .accessibilityValue("\(pressure.title). \(origin.explanation)")
    }

    private var powerIndicator: some View {
        let reading = store.latest?.power
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 9) {
                Image(systemName: "bolt.fill").foregroundStyle(.yellow).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Güç tüketimi").font(.caption.weight(.medium))
                    Text(reading?.source.title ?? "Desteklenen güç verisi alınamadı")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Text(reading?.text ?? "— W")
                    .font(.system(.body, design: .rounded).weight(.semibold)).monospacedDigit()
            }
            if reading != nil {
                Text("Sensör daha seyrek yenilenebilir.").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
        .help("Mac’in son güç sensörü ölçümüdür; prizden çekilen elektrik veya adaptörün kapasitesi değildir. Sensörün yenileme hızı uygulama aralığından farklı olabilir.")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Güç tüketimi")
        .accessibilityValue(reading.map { "\($0.text), \($0.source.title). Sensör daha seyrek yenilenebilir." }
                            ?? "Desteklenen güç verisi alınamadı")
    }

    private var temperatureIndicator: some View {
        let reading = store.latest?.temperature
        return HStack(spacing: 9) {
            Image(systemName: "thermometer.medium").foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Sıcaklık").font(.caption.weight(.medium))
                Text(reading?.source.title ?? "Desteklenen sensör okunamadı")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Text(reading?.text ?? "— °C")
                .font(.system(.body, design: .rounded).weight(.semibold))
                .monospacedDigit()
        }
        .padding(10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
        .help(reading.map { "Sensör: \($0.sensorName). Kasa veya ortam sıcaklığı değildir." }
              ?? "Bu Mac veya macOS sürümünde sıcaklık sensörüne erişilemiyor.")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sıcaklık")
        .accessibilityValue(reading.map { "\($0.text), \($0.source.title), \($0.sensorName)" }
                            ?? "Sıcaklık sensörü kullanılamıyor")
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

