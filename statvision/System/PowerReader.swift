import Foundation
import IOKit

/// One read-only registry snapshot per sample, on SystemSampler's utility queue.
/// SmartBattery fields are model-dependent and are not a stable public schema.
final class PowerReader {
    private var service: io_service_t = 0
    private var nextLookup: TimeInterval = 0

    func read(at timestamp: TimeInterval) -> PowerReading? {
        if service == 0 {
            guard timestamp >= nextLookup else { return nil }
            nextLookup = timestamp + 30
            service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        }
        guard service != 0 else { return nil }
        var properties: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0)
        let dictionary = properties?.takeRetainedValue() as? [String: Any]
        guard result == KERN_SUCCESS, let dictionary else {
            reset()
            nextLookup = timestamp + 30
            return nil
        }
        // Do not retain or log battery serials or other unrelated properties.
        return PowerCalculator.reading(from: PowerInput(registry: dictionary))
    }

    func reset() {
        if service != 0 { IOObjectRelease(service); service = 0 }
        nextLookup = 0
    }

    deinit { if service != 0 { IOObjectRelease(service) } }
}
