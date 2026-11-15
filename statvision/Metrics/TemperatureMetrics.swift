import Foundation

struct TemperatureSensorValue {
    let name: String
    let celsius: Double
}

enum TemperatureSource: Equatable {
    case chipHotspot, calibratedPMU

    var title: String {
        switch self {
        case .chipHotspot: return "Çip · en sıcak sensör"
        case .calibratedPMU: return "PMU sıcaklık sensörü"
        }
    }
}

struct TemperatureReading: Equatable {
    let celsius: Double
    let source: TemperatureSource
    let sensorName: String

    var text: String {
        celsius.formatted(.number.precision(.fractionLength(0))) + " °C"
    }
}

enum TemperatureSelection {
    static func source(for name: String) -> TemperatureSource? {
        if name.range(of: #"^PMU[0-9]* tdie[0-9]+$"#, options: .regularExpression) != nil {
            return .chipHotspot
        }
        if name.range(of: #"^PMU[0-9]* tcal$"#, options: .regularExpression) != nil {
            return .calibratedPMU
        }
        return nil
    }

    static func reading(from sensors: [TemperatureSensorValue]) -> TemperatureReading? {
        let valid = sensors.filter { $0.celsius.isFinite && $0.celsius > 0 && $0.celsius < 150 }
        // Chip die sensors take precedence. Never relabel a battery or an
        // unidentified ambient sensor as the computer's chip temperature.
        for source in [TemperatureSource.chipHotspot, .calibratedPMU] {
            let candidates = valid.filter { Self.source(for: $0.name) == source }
            if let hottest = candidates.sorted(by: {
                $0.celsius == $1.celsius ? $0.name < $1.name : $0.celsius > $1.celsius
            }).first {
                return TemperatureReading(celsius: hottest.celsius, source: source,
                                          sensorName: hottest.name)
            }
        }
        return nil
    }
}
