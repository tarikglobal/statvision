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

struct ApplicationUsage: Identifiable, Equatable {
    let id: String
    let name: String
    let cpuPercentage: Double?
    let memoryBytes: UInt64?
    let processCount: Int
}

enum ApplicationRanking: String, CaseIterable, Identifiable {
    case cpu = "CPU", memory = "RAM"
    var id: String { rawValue }
}

struct ApplicationUsageSnapshot: Equatable {
    let applications: [ApplicationUsage]
    let unreadableProcesses: Int

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

struct ApplicationUsageCalculator {
    private var previous: [Int32: ProcessResourceSample] = [:]

    mutating func reset() { previous.removeAll() }

    mutating func consume(_ samples: [ProcessResourceSample], secondsPerTick: Double,
                          processorCount: Int, maximumGap: TimeInterval,
                          unreadableProcesses: Int = 0) -> ApplicationUsageSnapshot {
        // Keeping only this scan also drops exited and temporarily unreadable PIDs.
        let current = Dictionary(samples.filter { $0.timestamp.isFinite }.map { ($0.pid, $0) },
                                 uniquingKeysWith: { _, newest in newest })
        defer { previous = current }
        var groups: [String: [ProcessResourceSample]] = [:]
        for sample in current.values { groups[sample.appID, default: []].append(sample) }
        let applications = groups.map { id, processes -> ApplicationUsage in
            var memory: UInt64? = 0
            var cpu: Double? = 0
            for process in processes {
                if let bytes = memory {
                    let sum = bytes.addingReportingOverflow(process.memoryBytes)
                    memory = sum.overflow ? nil : sum.partialValue
                }
                guard let old = previous[process.pid], old.startTime == process.startTime,
                      old.appID == process.appID, process.cpuTicks >= old.cpuTicks,
                      processorCount > 0, secondsPerTick.isFinite, secondsPerTick > 0 else {
                    cpu = nil
                    continue
                }
                let elapsed = process.timestamp - old.timestamp
                guard elapsed > 0, elapsed <= maximumGap else { cpu = nil; continue }
                let percentage = Double(process.cpuTicks - old.cpuTicks) * secondsPerTick
                    / elapsed / Double(processorCount) * 100
                guard percentage.isFinite else { cpu = nil; continue }
                if let value = cpu { cpu = value + percentage }
            }
            return ApplicationUsage(id: id, name: processes[0].appName,
                                    cpuPercentage: cpu.map { min(100, max(0, $0)) },
                                    memoryBytes: memory, processCount: processes.count)
        }
        return ApplicationUsageSnapshot(applications: applications,
                                        unreadableProcesses: unreadableProcesses)
    }
}
