import Darwin
import Foundation

/// Called exclusively on SystemSampler's utility queue while the panel is open.
final class ApplicationSampler {
    private var calculator = ApplicationUsageCalculator()
    private let secondsPerTick: Double
    private let processorCount = ProcessInfo.processInfo.processorCount

    init() {
        var timebase = mach_timebase_info_data_t()
        if mach_timebase_info(&timebase) == KERN_SUCCESS, timebase.denom > 0 {
            secondsPerTick = Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
        } else {
            secondsPerTick = .nan
        }
    }

    func reset() { calculator.reset() }

    func sample(applications: [ApplicationDescriptor], maximumGap: TimeInterval)
        -> ApplicationUsageSnapshot? {
        guard let pids = processIDs() else { reset(); return nil }
        let byPID = Dictionary(applications.map { ($0.pid, $0) },
                               uniquingKeysWith: { first, _ in first })
        // The outer application's bundle wins over nested helper .app bundles.
        let byPath = applications.sorted { $0.bundlePath.count < $1.bundlePath.count }
        var samples: [ProcessResourceSample] = []
        var unreadable = 0
        var found = Set<Int32>()
        for pid in pids where pid > 0 {
            // PROC_PIDPATHINFO_MAXSIZE's C macro is not imported by Swift.
            var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
            let pathLength = path.withUnsafeMutableBytes {
                proc_pidpath(pid, $0.baseAddress, UInt32($0.count))
            }
            let executable = pathLength > 0 ? String(cString: path) : ""
            guard let app = byPath.first(where: { executable.hasPrefix($0.bundlePath + "/") })
                    ?? byPID[pid] else { continue }
            found.insert(pid)
            var usage = rusage_info_v2()
            let result = withUnsafeMutablePointer(to: &usage) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V2, $0)
                }
            }
            let cpu = usage.ri_user_time.addingReportingOverflow(usage.ri_system_time)
            guard result == 0, usage.ri_proc_exit_abstime == 0, !cpu.overflow else {
                unreadable += 1
                continue
            }
            // rusage CPU counters are Mach absolute ticks, not nanoseconds on ARM.
            samples.append(ProcessResourceSample(pid: pid, startTime: usage.ri_proc_start_abstime,
                appID: app.bundlePath, appName: app.name, cpuTicks: cpu.partialValue,
                memoryBytes: usage.ri_phys_footprint, timestamp: SampleClock.now))
        }
        unreadable += byPID.keys.filter { !found.contains($0) }.count
        return calculator.consume(samples, secondsPerTick: secondsPerTick,
                                  processorCount: processorCount, maximumGap: maximumGap,
                                  unreadableProcesses: unreadable)
    }

    private func processIDs() -> [Int32]? {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return nil }
        var capacity = Int(estimate) + 128
        for _ in 0..<3 {
            var pids = [Int32](repeating: 0, count: capacity)
            let count = pids.withUnsafeMutableBytes {
                proc_listallpids($0.baseAddress, Int32($0.count))
            }
            guard count > 0 else { return nil }
            if Int(count) < capacity { return Array(pids.prefix(Int(count))) }
            capacity *= 2
        }
        return nil
    }
}
