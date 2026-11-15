import Darwin
import Foundation

/// Read-only, best-effort IOHID temperature access. These OS entry points are
/// undocumented: resolve every symbol at runtime and tolerate missing services.
/// All calls and retained Core Foundation objects stay on the sampling queue.
final class TemperatureReader {
    private var connection: HIDTemperatureConnection?
    private var nextDiscovery: TimeInterval = 0

    func read(at timestamp: TimeInterval) -> TemperatureReading? {
        if connection == nil && timestamp >= nextDiscovery {
            connection = HIDTemperatureConnection()
            nextDiscovery = timestamp + 30
        }
        guard let connection else { return nil }
        let result = TemperatureSelection.reading(from: connection.read())
        if result == nil {
            // Discard failed handles. Retry discovery with backoff rather than
            // continuously scanning a machine without supported sensors.
            self.connection = nil
            nextDiscovery = timestamp + 30
        }
        return result
    }

    func reset() {
        connection = nil
        nextDiscovery = 0
    }
}

private final class HIDTemperatureConnection {
    private typealias Create = @convention(c) (CFAllocator?) -> Unmanaged<CFTypeRef>?
    private typealias SetMatching = @convention(c) (CFTypeRef, CFDictionary) -> Void
    private typealias CopyServices = @convention(c) (CFTypeRef) -> Unmanaged<CFArray>?
    private typealias CopyProperty = @convention(c) (CFTypeRef, CFString) -> Unmanaged<CFTypeRef>?
    private typealias CopyEvent = @convention(c) (CFTypeRef, UInt32, Int32, UInt64) -> Unmanaged<CFTypeRef>?
    private typealias FloatValue = @convention(c) (CFTypeRef, Int32) -> Double

    private let library: UnsafeMutableRawPointer
    private let copyEvent: CopyEvent
    private let floatValue: FloatValue
    private var client: CFTypeRef?
    private var sensors: [(service: CFTypeRef, name: String)] = []

    init?() {
        guard let library = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY | RTLD_LOCAL)
        else { return nil }
        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            guard let address = dlsym(library, name) else { return nil }
            return unsafeBitCast(address, to: type)
        }
        guard let create = symbol("IOHIDEventSystemClientCreate", as: Create.self),
              let match = symbol("IOHIDEventSystemClientSetMatching", as: SetMatching.self),
              let services = symbol("IOHIDEventSystemClientCopyServices", as: CopyServices.self),
              let property = symbol("IOHIDServiceClientCopyProperty", as: CopyProperty.self),
              let event = symbol("IOHIDServiceClientCopyEvent", as: CopyEvent.self),
              let value = symbol("IOHIDEventGetFloatValue", as: FloatValue.self) else {
            dlclose(library)
            return nil
        }
        guard let client = create(kCFAllocatorDefault)?.takeRetainedValue() else {
            dlclose(library)
            return nil
        }
        self.library = library
        self.copyEvent = event
        self.floatValue = value
        self.client = client
        // Apple vendor temperature usage only. No keyboard/mouse matching,
        // event callbacks, input monitoring, property writes or run loop.
        match(client, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary)
        if let list = services(client)?.takeRetainedValue() {
            for index in 0..<CFArrayGetCount(list) {
                guard let pointer = CFArrayGetValueAtIndex(list, index) else { continue }
                let service = Unmanaged<CFTypeRef>.fromOpaque(pointer).takeUnretainedValue()
                guard let name = property(service, "Product" as CFString)?.takeRetainedValue() as? String,
                      TemperatureSelection.source(for: name) != nil else { continue }
                sensors.append((service: service, name: name))
            }
        }
    }

    func read() -> [TemperatureSensorValue] {
        sensors.compactMap { sensor in
            // IOHID temperature event type 15, temperature level field 15 << 16.
            guard let event = copyEvent(sensor.service, 15, 0, 0)?.takeRetainedValue() else { return nil }
            return TemperatureSensorValue(name: sensor.name, celsius: floatValue(event, 15 << 16))
        }
    }

    deinit {
        // Release CF services/client while their framework code is still loaded.
        sensors.removeAll()
        client = nil
        dlclose(library)
    }
}
