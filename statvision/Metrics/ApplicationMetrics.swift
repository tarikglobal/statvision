import Foundation

struct ApplicationDescriptor {
    let pid: Int32
    let name: String
    let bundlePath: String
}

struct ProcessResourceSample {
    let pid: Int32
    let startTime: UInt64
    let appID: String
    let appName: String
    let cpuTicks: UInt64
    let memoryBytes: UInt64
    let timestamp: TimeInterval
}

struct ProcessIdentity: Equatable, Hashable {
    let pid: Int32
    let startTime: UInt64
}

struct ApplicationUsage: Identifiable, Equatable {
    let id: String
    let name: String
    let cpuPercentage: Double?
    let memoryBytes: UInt64?
    let processCount: Int
    let processes: [ProcessIdentity]
    let cpuIsPartial: Bool

    init(id: String, name: String, cpuPercentage: Double?, memoryBytes: UInt64?,
         processCount: Int, processes: [ProcessIdentity] = [], cpuIsPartial: Bool = false) {
        self.id = id
        self.name = name
        self.cpuPercentage = cpuPercentage
        self.memoryBytes = memoryBytes
        self.processCount = processCount
        self.processes = processes
        self.cpuIsPartial = cpuIsPartial
    }
}

enum ApplicationTerminationPolicy {
    static func disabledReason(bundleIdentifier: String?, bundlePath: String,
                               isOwnApplication: Bool, isProhibited: Bool) -> String? {
        if isOwnApplication { return "statvision’ı kapatmak için Çıkış düğmesini kullanın." }
        guard let identifier = bundleIdentifier, !identifier.isEmpty else {
            return "Uygulama kimliği doğrulanamadı."
        }
        let protected: Set<String> = ["com.apple.finder", "com.apple.dock", "com.apple.loginwindow",
            "com.apple.controlcenter", "com.apple.systemuiserver", "com.apple.windowmanager",
            "com.apple.notificationcenterui", "com.apple.securityagent"]
        if isProhibited || protected.contains(identifier.lowercased())
            || bundlePath.hasPrefix("/System/Library/") {
            return "Bu sistem uygulaması buradan kapatılamaz."
        }
        return nil
    }

    static func matchesObservedProcess(_ current: ProcessIdentity?, observed: [ProcessIdentity]) -> Bool {
        guard let current, current.pid > 0, current.startTime > 0 else { return false }
        return observed.contains(current)
    }
}

enum ApplicationRanking: String, CaseIterable, Identifiable {
    case cpu = "CPU", memory = "RAM"
    var id: String { rawValue }
}

struct ApplicationUsageSnapshot: Equatable {
    let applications: [ApplicationUsage]
    let unreadableProcesses: Int
    let systemCPUPercentage: Double?

    init(applications: [ApplicationUsage], unreadableProcesses: Int, systemCPUPercentage: Double? = nil) {
        self.applications = applications
        self.unreadableProcesses = unreadableProcesses
        self.systemCPUPercentage = systemCPUPercentage
    }

    var cpuBreakdown: CPUUsageBreakdown? {
        guard let total = systemCPUPercentage, total.isFinite, (0...100).contains(total) else { return nil }
        let rows = topFive(by: .cpu)
        guard !rows.isEmpty else { return nil }
        let listed = rows.compactMap(\.cpuPercentage).reduce(0, +)
        guard listed.isFinite else { return nil }
        return CPUUsageBreakdown(total: total, listed: listed,
                                 otherOrUnmeasured: listed <= total ? total - listed : nil,
                                 isPartial: unreadableProcesses > 0 || rows.contains(where: \.cpuIsPartial))
    }

    func topFive(by ranking: ApplicationRanking) -> [ApplicationUsage] {
        applications.filter {
            ranking == .cpu ? $0.cpuPercentage != nil : $0.memoryBytes != nil
        }.sorted {
            if ranking == .cpu, $0.cpuPercentage != $1.cpuPercentage {
                return ($0.cpuPercentage ?? 0) > ($1.cpuPercentage ?? 0)
            }
            if ranking == .memory, $0.memoryBytes != $1.memoryBytes {
                return ($0.memoryBytes ?? 0) > ($1.memoryBytes ?? 0)
            }
            return $0.id < $1.id
        }.prefix(5).map { $0 }
    }
}

struct CPUUsageBreakdown: Equatable {
    let total: Double
    let listed: Double
    /// Residual, not a separate direct measurement. Includes every workload
    /// outside the five visible rows, plus unmeasured portions and system work.
    let otherOrUnmeasured: Double?
    let isPartial: Bool
}

struct ApplicationUsageCalculator {
    private var previous: [Int32: ProcessResourceSample] = [:]

    mutating func reset() { previous.removeAll() }

    mutating func consume(_ samples: [ProcessResourceSample], secondsPerTick: Double,
                          processorCount: Int, maximumGap: TimeInterval,
                          unreadableProcesses: Int = 0,
                          systemCPUPercentage: Double? = nil) -> ApplicationUsageSnapshot {
        // Keeping only this scan also drops exited and temporarily unreadable PIDs.
        let current = Dictionary(samples.filter { $0.timestamp.isFinite }.map { ($0.pid, $0) },
                                 uniquingKeysWith: { _, newest in newest })
        defer { previous = current }
        var groups: [String: [ProcessResourceSample]] = [:]
        for sample in current.values { groups[sample.appID, default: []].append(sample) }
        let applications = groups.map { id, processes -> ApplicationUsage in
            var memory: UInt64? = 0
            var cpu: Double = 0
            var measuredProcesses = 0
            for process in processes {
                if let bytes = memory {
                    let sum = bytes.addingReportingOverflow(process.memoryBytes)
                    memory = sum.overflow ? nil : sum.partialValue
                }
                guard let old = previous[process.pid], old.startTime == process.startTime,
                      old.appID == process.appID, process.cpuTicks >= old.cpuTicks,
                      processorCount > 0, secondsPerTick.isFinite, secondsPerTick > 0 else {
                    continue
                }
                let elapsed = process.timestamp - old.timestamp
                guard elapsed > 0, elapsed <= maximumGap else { continue }
                let percentage = Double(process.cpuTicks - old.cpuTicks) * secondsPerTick
                    / elapsed / Double(processorCount) * 100
                guard percentage.isFinite else { continue }
                cpu += percentage
                measuredProcesses += 1
            }
            return ApplicationUsage(id: id, name: processes[0].appName,
                                    cpuPercentage: measuredProcesses > 0 ? min(100, max(0, cpu)) : nil,
                                    memoryBytes: memory, processCount: processes.count,
                                    processes: processes.map { ProcessIdentity(pid: $0.pid, startTime: $0.startTime) }
                                        .sorted { $0.pid < $1.pid },
                                    cpuIsPartial: measuredProcesses < processes.count)
        }
        return ApplicationUsageSnapshot(applications: applications,
                                        unreadableProcesses: unreadableProcesses,
                                        systemCPUPercentage: systemCPUPercentage)
    }
}
