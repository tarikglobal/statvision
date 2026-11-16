import SwiftUI

struct ApplicationUsageView: View {
    let snapshot: ApplicationUsageSnapshot?
    let hasSample: Bool
    let disabledReason: (ApplicationUsage) -> String?
    let closeApplication: (ApplicationUsage) -> Void
    let terminationMessage: String?
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
                                HStack(spacing: 7) {
                                    Text(app.name).lineLimit(1).truncationMode(.tail)
                                    Spacer(minLength: 8)
                                    Text(value(for: app)).monospacedDigit()
                                        .foregroundStyle(ranking == .cpu ? Color.blue : Color.teal)
                                }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("\(index + 1). \(app.name)")
                                .accessibilityValue("\(ranking.rawValue) \(value(for: app)), \(app.processCount) işlem")
                                .help("\(app.name) · \(app.processCount) işlem")
                                Button { closeApplication(app) } label: {
                                    Image(systemName: "xmark.circle")
                                        .font(.system(size: 13))
                                        .frame(width: 22, height: 22)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.secondary)
                                .disabled(disabledReason(app) != nil)
                                .help(disabledReason(app) ?? "\(app.name) uygulamasını kapat")
                                .accessibilityLabel("\(app.name) uygulamasını kapat")
                                .accessibilityHint(disabledReason(app) ?? "Uygulamaya normal kapatma isteği gönderir")
                            }
                            .font(.caption)
                            .frame(height: 22)
                            .accessibilityElement(children: .contain)
                        }
                    }
                } else {
                    Text(hasSample ? "Uygulama verileri okunamadı." : "Uygulamalar ölçülüyor…")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 110)
                }
            }
            .frame(minHeight: 138, alignment: .top)
            if ranking == .cpu, let breakdown = snapshot?.cpuBreakdown {
                VStack(spacing: 4) {
                    cpuShare("Toplam CPU", value: breakdown.total)
                    cpuShare("Bu 5 satırda ölçülen", value: breakdown.listed)
                    cpuShare("Diğer / ölçülemeyen", value: breakdown.otherOrUnmeasured)
                }
                .font(.caption2)
                .help("Diğer / ölçülemeyen, toplam CPU ile bu beş satırda ölçülen payın farkıdır. Sistem işlemleri, arka plan işleri, diğer uygulamalar ve eksik ölçümler bu farkın içindedir.")
                if breakdown.otherOrUnmeasured == nil {
                    Text("Ölçüm farkı var; sonraki örnek bekleniyor.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            if ranking == .cpu, snapshot?.topFive(by: .cpu).contains(where: \.cpuIsPartial) == true {
                Text("≥ işareti: yardımcı işlemlerin bir kısmı için yeni ölçüm bekleniyor.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let terminationMessage {
                Text(terminationMessage).font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Kapatma durumu: \(terminationMessage)")
            }
            Text((snapshot?.unreadableProcesses ?? 0) > 0
                 ? "Bazı işlemler okunamadı; liste eksik olabilir."
                 : "Yalnızca ilk 5 uygulama · CPU: tüm sistem %100")
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func cpuShare(_ title: String, value: Double?) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value.map { $0.formatted(.number.precision(.fractionLength(1))) + "%" } ?? "—")
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private func value(for app: ApplicationUsage) -> String {
        switch ranking {
        case .cpu:
            guard let percentage = app.cpuPercentage else { return "—" }
            return (app.cpuIsPartial ? "≥ " : "") + percentage.formatted(.number.precision(.fractionLength(1))) + "%"
        case .memory:
            guard let bytes = app.memoryBytes else { return "—" }
            let gb = Double(bytes) / 1_073_741_824
            if gb >= 1 { return gb.formatted(.number.precision(.fractionLength(2))) + " GB" }
            return (Double(bytes) / 1_048_576).formatted(.number.precision(.fractionLength(0))) + " MB"
        }
    }
}
