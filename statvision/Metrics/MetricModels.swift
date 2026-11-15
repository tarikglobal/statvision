import Foundation

enum CPUStatus: Equatable {
    case valid, warmingUp, unavailable, invalidCounter, zeroDelta, interrupted, sleeping

    var explanation: String {
        switch self {
        case .valid: return "Ardışık sayaçlar arasındaki ortalama"
        case .warmingUp: return "İlk CPU ölçümü hazırlanıyor…"
        case .unavailable: return "CPU sayaçları okunamadı"
        case .invalidCounter: return "Sayaç değişimi geçersiz; yeniden ölçülüyor"
        case .zeroDelta: return "Sayaçlar ilerlemedi; sonraki ölçüm bekleniyor"
        case .interrupted: return "Ölçüm kesintisi; yeniden ölçülüyor"
        case .sleeping: return "Mac uyku durumunda"
        }
    }
}

struct CPUReading: Equatable {
    let percentage: Double?
    let status: CPUStatus
}

struct CPUTicks: Equatable {
    let user: UInt32
    let system: UInt32
    let idle: UInt32
    let nice: UInt32
    let timestamp: TimeInterval
}

struct MemoryPages {
    let anonymous: UInt64
    let purgeable: UInt64
    let wired: UInt64
    let compressed: UInt64
    let fileBacked: UInt64
    let pageSize: UInt64
    let totalBytes: UInt64
}

struct MemoryReading: Equatable {
    let usedBytes: UInt64
    let totalBytes: UInt64
    let compressedBytes: UInt64
    let cachedBytes: UInt64

    var percentage: Double { Double(usedBytes) / Double(totalBytes) * 100 }
    // RAM capacity uses the binary scale (GiB), labelled GB throughout the UI.
    // Apply the same scale to used and total bytes; percentage stays byte-based.
    private static let bytesPerGB: Double = 1_073_741_824
    var usedGB: Double { Double(usedBytes) / Self.bytesPerGB }
    var totalGB: Double { Double(totalBytes) / Self.bytesPerGB }
}

enum MemoryPressure: Equatable {
    case normal, warning, critical, unavailable

    // The sysctl returns DISPATCH pressure flags, NOT internal XNU enum values.
    init(dispatchFlags: UInt32) {
        switch dispatchFlags {
        case 1: self = .normal
        case 2: self = .warning
        case 4: self = .critical
        default: self = .unavailable
        }
    }

    var title: String {
        switch self {
        case .normal: return "Normal"
        case .warning: return "Yükselmiş"
        case .critical: return "Kritik"
        case .unavailable: return "Kullanılamıyor"
        }
    }
}

enum PressureSource: Equatable {
    case systemSnapshot, notification, unavailable

    var explanation: String {
        switch self {
        case .systemSnapshot: return "Sistemin bellek baskısı seviyesi"
        case .notification: return "Son sistem bildirimi; anlık sorgu kullanılamıyor"
        case .unavailable: return "Sistem verisi yok; doluluk oranından tahmin edilmez"
        }
    }
}

struct SystemSample: Equatable {
    /// Monotonic seconds including sleep. Wall-clock changes never distort charts.
    let timestamp: TimeInterval
    let cpu: CPUReading
    let memory: MemoryReading?
    let pressure: MemoryPressure
    let pressureSource: PressureSource
    let temperature: TemperatureReading?

    init(timestamp: TimeInterval, cpu: CPUReading, memory: MemoryReading?,
         pressure: MemoryPressure, pressureSource: PressureSource,
         temperature: TemperatureReading? = nil) {
        self.timestamp = timestamp
        self.cpu = cpu
        self.memory = memory
        self.pressure = pressure
        self.pressureSource = pressureSource
        self.temperature = temperature
    }
}

struct MenuBarVisibility: Equatable {
    var showCPU = true
    var showMemory = true
    var showTemperature = true
}

struct MenuBarPresentation {
    let title: String
    let accessibilityValue: String
    let toolTip: String

    static func make(sample: SystemSample?, visibility: MenuBarVisibility) -> MenuBarPresentation {
        var titles: [String] = []
        var descriptions: [String] = []
        if visibility.showCPU {
            let cpu = sample?.cpu.percentage.map {
                $0.formatted(.number.precision(.fractionLength(0))) + "%"
            } ?? "—"
            titles.append("CPU \(cpu)")
            descriptions.append("CPU \(cpu)")
        }
        if visibility.showMemory {
            let memory = sample?.memory.map {
                $0.usedGB.formatted(.number.precision(.fractionLength(1))) + " GB"
            } ?? "—"
            titles.append("RAM \(memory)")
            descriptions.append("Kullanılan RAM \(memory)")
        }
        if visibility.showTemperature {
            let temperature = sample?.temperature?.text ?? "— °C"
            titles.append(temperature)
            descriptions.append("Sıcaklık \(temperature)")
        }
        var toolTip = (["statvision"] + titles).joined(separator: " · ")
        if visibility.showTemperature {
            toolTip += "\n" + (sample?.temperature.map { "\($0.source.title) · \($0.sensorName)" }
                ?? "Sıcaklık sensörü kullanılamıyor")
        }
        return MenuBarPresentation(title: titles.joined(separator: "  "),
                                   accessibilityValue: descriptions.isEmpty ? "Sistem izleme" : descriptions.joined(separator: ", "),
                                   toolTip: toolTip)
    }
}

struct SampleHistory {
    static let duration: TimeInterval = 60
    private(set) var samples: [SystemSample] = []

    mutating func append(_ sample: SystemSample) {
        guard sample.timestamp.isFinite else { return }
        if let last = samples.last, sample.timestamp <= last.timestamp {
            // Reject duplicate or out-of-order callbacks rather than drawing backwards.
            return
        }
        samples.removeAll { $0.timestamp < sample.timestamp - Self.duration }
        samples.append(sample)
    }

    func visible(at end: TimeInterval) -> [SystemSample] {
        samples.filter { $0.timestamp >= end - Self.duration && $0.timestamp <= end }
    }
}

