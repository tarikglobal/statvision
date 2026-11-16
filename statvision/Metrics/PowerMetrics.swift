import CoreFoundation
import Foundation

enum PowerSource: Equatable {
    case systemLoad, batteryDischarge

    var title: String {
        switch self {
        case .systemLoad: return "Sistem yükü · son sensör verisi"
        case .batteryDischarge: return "Pil deşarjı · son sensör verisi"
        }
    }
}

struct PowerReading: Equatable {
    let watts: Double
    let source: PowerSource

    var text: String { watts.formatted(.number.precision(.fractionLength(1))) + " W" }
}

struct PowerInput {
    let systemLoadMilliwatts: Double?
    let millivolts: Double?
    let milliamps: Int64?
    let externalConnected: Bool?
    let isCharging: Bool?

    init(registry: [String: Any]) {
        func number(_ value: Any?) -> NSNumber? {
            guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
            return value
        }
        let telemetry = registry["PowerTelemetryData"] as? [String: Any]
        systemLoadMilliwatts = number(telemetry?["SystemLoad"])?.doubleValue
        millivolts = number(registry["Voltage"])?.doubleValue
        // IORegistry can encode a negative current as unsigned two's complement.
        milliamps = (number(registry["InstantAmperage"]) ?? number(registry["Amperage"]))?.int64Value
        externalConnected = registry["ExternalConnected"] as? Bool
        isCharging = registry["IsCharging"] as? Bool
    }
}

enum PowerCalculator {
    static func reading(from input: PowerInput) -> PowerReading? {
        if let milliwatts = input.systemLoadMilliwatts, valid(milliwatts / 1000) {
            return PowerReading(watts: milliwatts / 1000, source: .systemLoad)
        }
        // V × A measures the battery flow, not system consumption on AC.
        // Never turn charging power, an adapter rating or CPU % into watts.
        guard input.externalConnected == false, input.isCharging == false,
              let millivolts = input.millivolts, millivolts.isFinite, millivolts > 0,
              let milliamps = input.milliamps, milliamps < 0 else { return nil }
        let watts = millivolts * -Double(milliamps) / 1_000_000
        guard valid(watts) else { return nil }
        return PowerReading(watts: watts, source: .batteryDischarge)
    }

    private static func valid(_ watts: Double) -> Bool {
        // Zero is an unsupported/stopped sensor for an awake laptop. Reject
        // corrupt/signed-underflow values rather than clamping or inventing data.
        watts.isFinite && watts > 0 && watts < 1000
    }
}
