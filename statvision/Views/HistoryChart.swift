import SwiftUI

enum ChartMetric {
    case cpu, memory
    func value(in sample: SystemSample) -> Double? {
        switch self {
        case .cpu: return sample.cpu.percentage
        case .memory: return sample.memory?.percentage
        }
    }
}

/// Static Canvas: no animation, TimelineView, display link or separate timer.
/// X is the actual monotonic timestamp, never the sample index.
struct HistoryChart: View {
    let title: String
    let samples: [SystemSample]
    let end: TimeInterval
    let metric: ChartMetric
    let color: Color
    let currentPercentage: Double?
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.caption.weight(.semibold))
                Spacer()
                Text(currentPercentageText)
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(color)
                    .help("Son ölçümdeki kullanım yüzdesi")
            }
            Canvas { context, size in
                let top: CGFloat = 3
                let height = max(1, size.height - 6)
                for fraction in [0.0, 0.5, 1.0] {
                    let y = top + height * (1 - fraction)
                    var grid = Path()
                    grid.move(to: CGPoint(x: 0, y: y))
                    grid.addLine(to: CGPoint(x: size.width, y: y))
                    context.stroke(grid, with: .color(.secondary.opacity(contrast == .increased ? 0.5 : 0.18)),
                                   style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                }
                var line = Path()
                var previous: SystemSample?
                for sample in samples {
                    guard let value = metric.value(in: sample), value.isFinite else {
                        previous = nil
                        continue
                    }
                    let x = (sample.timestamp - (end - SampleHistory.duration)) / SampleHistory.duration
                    guard (0...1).contains(x) else { previous = nil; continue }
                    let point = CGPoint(x: size.width * x, y: top + height * (1 - min(100, max(0, value)) / 100))
                    // The slowest allowed interval is 5 seconds. Larger gaps
                    // remain visible, including sleep or failed sample periods.
                    if let previous, sample.timestamp - previous.timestamp <= 7.5 {
                        line.addLine(to: point)
                    } else {
                        line.move(to: point)
                    }
                    previous = sample
                    context.fill(Path(ellipseIn: CGRect(x: point.x - 1.4, y: point.y - 1.4,
                                                       width: 2.8, height: 2.8)), with: .color(color))
                }
                context.stroke(line, with: .color(color),
                               style: StrokeStyle(lineWidth: contrast == .increased ? 2.5 : 1.8,
                                                  lineCap: .round, lineJoin: .round))
            }
            .frame(height: 48)
            .clipped()
            .overlay {
                if samples.allSatisfy({ metric.value(in: $0) == nil }) {
                    Text("Ölçüm bekleniyor").font(.caption2).foregroundStyle(.secondary)
                }
            }
            HStack {
                Text("−60 sn")
                Spacer()
                Text("Şimdi")
            }.font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), son 60 saniyelik kullanım grafiği")
        .accessibilityValue(accessibilitySummary)
    }

    private var currentPercentageText: String {
        guard let currentPercentage, currentPercentage.isFinite else { return "—" }
        return currentPercentage.formatted(.number.precision(.fractionLength(0))) + "%"
    }

    private var accessibilitySummary: String {
        let values = samples.compactMap { metric.value(in: $0) }
        guard let minimum = values.min(), let maximum = values.max() else {
            return "Henüz ölçüm yok"
        }
        func percent(_ value: Double) -> String {
            value.formatted(.number.precision(.fractionLength(0))) + "%"
        }
        let current = currentPercentage == nil ? "Anlık ölçüm kullanılamıyor" : "Anlık \(currentPercentageText)"
        return "\(current), en düşük \(percent(minimum)), en yüksek \(percent(maximum)). Eksik ölçümler grafikte boşluk bırakır."
    }
}

