import Darwin
import Foundation

enum SampleClock {
    // Darwin CLOCK_MONOTONIC_RAW includes sleep and cannot jump with wall time.
    static var now: TimeInterval {
        Double(clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)) / 1_000_000_000
    }
}

/// All mutable measurement state and Mach calls belong to this serial queue.
/// The UI only receives immutable value snapshots.
final class SystemSampler {
    var onSample: ((SystemSample) -> Void)?
    private let queue = DispatchQueue(label: "com.statvision.sampling", qos: .utility)
    private let reader = SystemReader()
    private let applicationSampler = ApplicationSampler()
    private let temperatureReader = TemperatureReader()
    private let powerReader = PowerReader()
    private var applications: [ApplicationDescriptor] = []
    private var applicationSession: UUID?
    private var timer: DispatchSourceTimer?
    private var pressureSource: DispatchSourceMemoryPressure?
    private var notifiedPressure: MemoryPressure = .unavailable
    private var calculator = CPUCalculator()
    private var interval: TimeInterval = 2

    func start(interval: TimeInterval) {
        queue.async { [weak self] in
            self?.restartOnQueue(interval: interval)
        }
    }

    private func restartOnQueue(interval: TimeInterval) {
        self.interval = [1.0, 2.0, 5.0].contains(interval) ? interval : 2
        timer?.cancel()
        calculator.reset()
        applicationSampler.reset()
        installPressureSourceIfNeeded()
        sample()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + self.interval, repeating: self.interval,
                       leeway: .milliseconds(150))
        timer.setEventHandler { [weak self] in self?.sample() }
        self.timer = timer
        timer.resume()
    }

    func pauseForSleep() {
        queue.async { [weak self] in
            guard let self else { return }
            self.cancelSources()
            self.calculator.reset()
            self.onSample?(SystemSample(timestamp: SampleClock.now,
                cpu: CPUReading(percentage: nil, status: .sleeping), memory: nil,
                pressure: .unavailable, pressureSource: .unavailable))
        }
    }

    func stop() {
        queue.async { [weak self] in self?.cancelSources() }
    }

    func setApplications(_ applications: [ApplicationDescriptor], session: UUID?) {
        queue.async { [weak self] in
            guard let self else { return }
            let changedSession = self.applicationSession != session
            self.applications = applications
            self.applicationSession = session
            if changedSession {
                self.applicationSampler.reset()
                // Both CPU counters start a fresh, common measurement interval.
                if session != nil { self.restartOnQueue(interval: self.interval) }
            }
        }
    }

    private func cancelSources() {
        timer?.cancel()
        timer = nil
        pressureSource?.cancel()
        pressureSource = nil
        notifiedPressure = .unavailable
        applicationSampler.reset()
        temperatureReader.reset()
        powerReader.reset()
    }

    private func installPressureSourceIfNeeded() {
        guard pressureSource == nil else { return }
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.normal, .warning, .critical], queue: queue)
        source.setEventHandler { [weak self] in
            guard let self, let source = self.pressureSource else { return }
            let flags = source.data
            // Coalesced notifications: conservatively prefer the highest level.
            if flags.contains(.critical) { self.notifiedPressure = .critical }
            else if flags.contains(.warning) { self.notifiedPressure = .warning }
            else if flags.contains(.normal) { self.notifiedPressure = .normal }
        }
        pressureSource = source
        source.resume()
    }

    private func sample() {
        let timestamp = SampleClock.now
        let cpu: CPUReading
        if let ticks = reader.cpuTicks(at: timestamp) {
            cpu = calculator.consume(ticks, maximumGap: max(15, interval * 3))
        } else {
            calculator.reset()
            cpu = CPUReading(percentage: nil, status: .unavailable)
        }
        // Read application counters immediately after host counters, with the
        // same timestamp. Publish one frame instead of independently timed UI updates.
        let applicationSnapshot = applicationSession == nil ? nil : applicationSampler.sample(
            applications: applications, maximumGap: max(15, interval * 3),
            at: timestamp, systemCPUPercentage: cpu.percentage)
        let pressure = reader.memoryPressure()
        let resolvedPressure = pressure != .unavailable ? pressure : notifiedPressure
        let origin: PressureSource = pressure != .unavailable ? .systemSnapshot
            : (notifiedPressure != .unavailable ? .notification : .unavailable)
        onSample?(SystemSample(timestamp: timestamp, cpu: cpu, memory: reader.memory(),
                               pressure: resolvedPressure, pressureSource: origin,
                               temperature: temperatureReader.read(at: timestamp),
                               power: powerReader.read(at: timestamp),
                               applications: applicationSnapshot, applicationSession: applicationSession))
    }

    deinit {
        timer?.cancel()
        pressureSource?.cancel()
    }
}

private final class SystemReader {
    // mach_host_self() acquires a send right. Reuse and release it, rather than
    // leaking one reference on every sample.
    private let host = mach_host_self()
    private let totalMemory = ProcessInfo.processInfo.physicalMemory

    func cpuTicks(at timestamp: TimeInterval) -> CPUTicks? {
        var info = host_cpu_load_info_data_t()
        let capacity = MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
        var count = mach_msg_type_number_t(capacity)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: capacity) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS, count == mach_msg_type_number_t(capacity) else { return nil }
        // HOST_CPU_LOAD_INFO aggregates all logical processors, so the ratio
        // is already normalized to 0–100%; never divide by the core count again.
        return CPUTicks(user: info.cpu_ticks.0, system: info.cpu_ticks.1,
                        idle: info.cpu_ticks.2, nice: info.cpu_ticks.3, timestamp: timestamp)
    }

    func memory() -> MemoryReading? {
        var pageSize: vm_size_t = 0
        guard host_page_size(host, &pageSize) == KERN_SUCCESS, pageSize > 0 else { return nil }
        var info = vm_statistics64_data_t()
        let capacity = MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        var count = mach_msg_type_number_t(capacity)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: capacity) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        // New SDKs may append fields that older supported kernels do not return.
        // Only require the fields used by our formula, through internal_page_count.
        guard let lastOffset = MemoryLayout<vm_statistics64_data_t>.offset(of: \.internal_page_count)
        else { return nil }
        let requiredBytes = lastOffset + MemoryLayout<natural_t>.size
        guard result == KERN_SUCCESS,
              Int(count) * MemoryLayout<integer_t>.size >= requiredBytes,
              Int(count) <= capacity else { return nil }
        return MemoryCalculator.calculate(MemoryPages(
            anonymous: UInt64(info.internal_page_count), purgeable: UInt64(info.purgeable_count),
            wired: UInt64(info.wire_count), compressed: UInt64(info.compressor_page_count),
            fileBacked: UInt64(info.external_page_count), pageSize: UInt64(pageSize),
            totalBytes: totalMemory))
    }

    func memoryPressure() -> MemoryPressure {
        // Best-effort read-only XNU sysctl; not a stable documented public API.
        // No privilege escalation and no fallback based on RAM occupancy.
        var flags: UInt32 = 0
        var size = MemoryLayout<UInt32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &flags, &size, nil, 0) == 0,
              size == MemoryLayout<UInt32>.size else { return .unavailable }
        return MemoryPressure(dispatchFlags: flags)
    }

    deinit { mach_port_deallocate(mach_task_self_, host) }
}

