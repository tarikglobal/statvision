import SwiftUI

struct ApplicationUsageView: View {
    let snapshot: ApplicationUsageSnapshot?
    let hasSample: Bool
    @State private var ranking: ApplicationRanking = .cpu

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Picker("Sıralama", selection: $ranking) {
                ForEach(ApplicationRanking.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("En çok tüketen uygulamaları sıralama")

            VStack(spacing: 7) {
                if let snapshot {
                    let rows = snapshot.topFive(by: ranking)
                    if rows.isEmpty {
                        Text(ranking == .cpu && !snapshot.applications.isEmpty
                             ? "İlk CPU ölçümü hazırlanıyor…"
                             : "Ölçülebilen uygulama bulunamadı.")
                            .font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 110, alignment: .center)
                    } else {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, app in
                            HStack(spacing: 7) {
                                Text("\(index + 1)").foregroundStyle(.secondary)
                                    .frame(width: 12, alignment: .leading)
                                Text(app.name).lineLimit(1).truncationMode(.tail)
                                Spacer(minLength: 8)
                                Text(value(for: app)).monospacedDigit()
                                    .foregroundStyle(ranking == .cpu ? Color.blue : Color.teal)
                            }
                            .font(.caption)
                            .frame(height: 18)
                            .help("\(app.name) · \(app.processCount) işlem")
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(index + 1). \(app.name)")
                            .accessibilityValue("\(ranking.rawValue) \(value(for: app)), \(app.processCount) işlem")
                        }
                    }
                } else {
                    Text(hasSample ? "Uygulama verileri okunamadı." : "Uygulamalar ölçülüyor…")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 110)
                }
            }
            .frame(minHeight: 118, alignment: .top)
            Text((snapshot?.unreadableProcesses ?? 0) > 0
                 ? "Bazı işlemler okunamadı; liste eksik olabilir."
                 : "Yardımcı işlemler dahil · CPU: toplam kapasite %100")
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func value(for app: ApplicationUsage) -> String {
        switch ranking {
        case .cpu:
            guard let percentage = app.cpuPercentage else { return "—" }
            return percentage.formatted(.number.precision(.fractionLength(1))) + "%"
        case .memory:
            guard let bytes = app.memoryBytes else { return "—" }
            let gb = Double(bytes) / 1_073_741_824
            if gb >= 1 { return gb.formatted(.number.precision(.fractionLength(2))) + " GB" }
            return (Double(bytes) / 1_048_576).formatted(.number.precision(.fractionLength(0))) + " MB"
        }
    }
}
