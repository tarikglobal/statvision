import Foundation

struct CPUCalculator {
    private var previous: CPUTicks?

    mutating func reset() { previous = nil }

    mutating func consume(_ current: CPUTicks, maximumGap: TimeInterval) -> CPUReading {
        guard current.timestamp.isFinite else {
            reset()
            return CPUReading(percentage: nil, status: .invalidCounter)
        }
        defer { previous = current }
        guard let previous else {
            return CPUReading(percentage: nil, status: .warmingUp)
        }
        let elapsed = current.timestamp - previous.timestamp
        guard elapsed > 0, elapsed <= maximumGap else {
            return CPUReading(percentage: nil, status: .interrupted)
        }
        // A decrease can be a counter reset or 32-bit wrap. Discard one interval
        // in either case; the next sample establishes an unambiguous delta.
        guard current.user >= previous.user, current.system >= previous.system,
              current.idle >= previous.idle, current.nice >= previous.nice else {
            return CPUReading(percentage: nil, status: .invalidCounter)
        }
        let user = UInt64(current.user - previous.user)
        let system = UInt64(current.system - previous.system)
        let nice = UInt64(current.nice - previous.nice)
        let idle = UInt64(current.idle - previous.idle)
        let busy = user + system + nice
        let total = busy + idle
        guard total > 0 else {
            return CPUReading(percentage: nil, status: .zeroDelta)
        }
        return CPUReading(percentage: min(100, max(0, Double(busy) / Double(total) * 100)),
                          status: .valid)
    }
}

enum MemoryCalculator {
    static func calculate(_ pages: MemoryPages) -> MemoryReading? {
        guard pages.pageSize > 0, pages.totalBytes > 0 else { return nil }
        // Purgeable anonymous pages are reclaimable, not app memory in use.
        // Compressor physical pages are counted once; the uncompressed logical
        // size and swapped-out pages are intentionally not added to physical RAM.
        let appPages = pages.anonymous > pages.purgeable
            ? pages.anonymous - pages.purgeable : 0
        guard let resident = add(appPages, pages.wired),
              let usedPages = add(resident, pages.compressed),
              let used = multiply(usedPages, pages.pageSize),
              let compressed = multiply(pages.compressed, pages.pageSize),
              let cachePages = add(pages.fileBacked, pages.purgeable),
              let cached = multiply(cachePages, pages.pageSize),
              used <= pages.totalBytes,
              compressed <= pages.totalBytes, cached <= pages.totalBytes else {
            // Inconsistent or overflowing snapshots are missing data, never 100%.
            return nil
        }
        return MemoryReading(usedBytes: used, totalBytes: pages.totalBytes,
                             compressedBytes: compressed, cachedBytes: cached)
    }

    private static func add(_ a: UInt64, _ b: UInt64) -> UInt64? {
        let result = a.addingReportingOverflow(b)
        return result.overflow ? nil : result.partialValue
    }

    private static func multiply(_ a: UInt64, _ b: UInt64) -> UInt64? {
        let result = a.multipliedReportingOverflow(by: b)
        return result.overflow ? nil : result.partialValue
    }
}

