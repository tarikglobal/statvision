import XCTest
#if SWIFT_PACKAGE
@testable import StatvisionMetrics
#else
@testable import statvision
#endif

final class CPUCalculatorTests: XCTestCase {
    private func ticks(_ user: UInt32 = 100, _ system: UInt32 = 50,
                       _ idle: UInt32 = 850, _ nice: UInt32 = 0,
                       at timestamp: Double = 1) -> CPUTicks {
        CPUTicks(user: user, system: system, idle: idle, nice: nice, timestamp: timestamp)
    }

    func testFirstSampleIsMissingRatherThanZero() {
        var calculator = CPUCalculator()
        let result = calculator.consume(ticks(), maximumGap: 15)
        XCTAssertNil(result.percentage)
        XCTAssertEqual(result.status, .warmingUp)
    }

    func testUsesIntervalDeltasInsteadOfLifetimeAverage() throws {
        var calculator = CPUCalculator()
        _ = calculator.consume(ticks(), maximumGap: 15)
        // 30 user + 20 system + 10 nice + 40 idle = 60% of total capacity.
        let result = calculator.consume(ticks(130, 70, 890, 10, at: 3), maximumGap: 15)
        XCTAssertEqual(try XCTUnwrap(result.percentage), 60, accuracy: 0.0001)
        XCTAssertEqual(result.status, .valid)
    }

    func testIdleAndFullyBusyEndpoints() throws {
        var calculator = CPUCalculator()
        _ = calculator.consume(ticks(), maximumGap: 15)
        let idle = calculator.consume(ticks(100, 50, 950, at: 3), maximumGap: 15)
        let busy = calculator.consume(ticks(200, 50, 950, at: 5), maximumGap: 15)
        XCTAssertEqual(try XCTUnwrap(idle.percentage), 0)
        XCTAssertEqual(try XCTUnwrap(busy.percentage), 100)
    }

    func testAggregatedMulticoreCountersStayBelowOneHundred() throws {
        var calculator = CPUCalculator()
        _ = calculator.consume(ticks(0, 0, 0, at: 0), maximumGap: 15)
        // Eight logical cores accumulating 200 ticks each: 800 / 1600 = 50%.
        let result = calculator.consume(ticks(600, 200, 800, at: 2), maximumGap: 15)
        XCTAssertEqual(try XCTUnwrap(result.percentage), 50)
    }

    func testNoProgressDoesNotInventZeroPercent() {
        var calculator = CPUCalculator()
        _ = calculator.consume(ticks(), maximumGap: 15)
        let result = calculator.consume(ticks(at: 3), maximumGap: 15)
        XCTAssertNil(result.percentage)
        XCTAssertEqual(result.status, .zeroDelta)
    }

    func testCounterResetDiscardsOnlyOneInterval() throws {
        var calculator = CPUCalculator()
        _ = calculator.consume(ticks(), maximumGap: 15)
        let invalid = calculator.consume(ticks(10, 10, 10, at: 3), maximumGap: 15)
        XCTAssertEqual(invalid.status, .invalidCounter)
        XCTAssertNil(invalid.percentage)
        let recovered = calculator.consume(ticks(20, 20, 30, at: 5), maximumGap: 15)
        XCTAssertEqual(try XCTUnwrap(recovered.percentage), 50)
    }

    func testUInt32WrapIsDiscardedWithoutUnderflow() {
        var calculator = CPUCalculator()
        _ = calculator.consume(ticks(.max - 2, 0, 0, at: 1), maximumGap: 15)
        let result = calculator.consume(ticks(3, 0, 10, at: 3), maximumGap: 15)
        XCTAssertNil(result.percentage)
        XCTAssertEqual(result.status, .invalidCounter)
    }

    func testSleepAndLongGapsRequireANewBaseline() {
        var calculator = CPUCalculator()
        _ = calculator.consume(ticks(), maximumGap: 15)
        let interrupted = calculator.consume(ticks(200, 100, 1700, at: 100), maximumGap: 15)
        XCTAssertNil(interrupted.percentage)
        XCTAssertEqual(interrupted.status, .interrupted)
        calculator.reset()
        XCTAssertEqual(calculator.consume(ticks(at: 102), maximumGap: 15).status, .warmingUp)
    }

    func testDuplicateBackwardAndNonfiniteTimesAreRejected() {
        var calculator = CPUCalculator()
        _ = calculator.consume(ticks(at: 10), maximumGap: 15)
        XCTAssertEqual(calculator.consume(ticks(at: 10), maximumGap: 15).status, .interrupted)
        XCTAssertEqual(calculator.consume(ticks(at: 9), maximumGap: 15).status, .interrupted)
        XCTAssertEqual(calculator.consume(ticks(at: .nan), maximumGap: 15).status, .invalidCounter)
        XCTAssertEqual(calculator.consume(ticks(at: 12), maximumGap: 15).status, .warmingUp)
    }
}

final class MemoryCalculatorTests: XCTestCase {
    private func pages(anonymous: UInt64 = 400, purgeable: UInt64 = 50,
                       wired: UInt64 = 100, compressed: UInt64 = 80,
                       fileBacked: UInt64 = 200, pageSize: UInt64 = 16_384,
                       total: UInt64 = 16_384_000) -> MemoryPages {
        MemoryPages(anonymous: anonymous, purgeable: purgeable, wired: wired,
                    compressed: compressed, fileBacked: fileBacked,
                    pageSize: pageSize, totalBytes: total)
    }

    func testCountsPhysicalCompressionOnceAndExcludesReclaimableCache() throws {
        let result = try XCTUnwrap(MemoryCalculator.calculate(pages()))
        // (400 anonymous - 50 purgeable + 100 wired + 80 compressor) * 16384.
        XCTAssertEqual(result.usedBytes, 530 * 16_384)
        XCTAssertEqual(result.compressedBytes, 80 * 16_384)
        XCTAssertEqual(result.cachedBytes, 250 * 16_384)
        XCTAssertEqual(result.percentage, 53, accuracy: 0.0001)
    }

    func testAddingFileCacheDoesNotIncreaseUsedMemory() throws {
        let first = try XCTUnwrap(MemoryCalculator.calculate(pages(fileBacked: 0)))
        let second = try XCTUnwrap(MemoryCalculator.calculate(pages(fileBacked: 350)))
        XCTAssertEqual(first.usedBytes, second.usedBytes)
        XCTAssertGreaterThan(second.cachedBytes, first.cachedBytes)
    }

    func testUsesRuntimePageSizeForIntelAndAppleSilicon() throws {
        let small = try XCTUnwrap(MemoryCalculator.calculate(pages(pageSize: 4096)))
        let large = try XCTUnwrap(MemoryCalculator.calculate(pages(pageSize: 16_384)))
        XCTAssertEqual(large.usedBytes, small.usedBytes * 4)
    }

    func testPurgeableLargerThanAnonymousCannotUnderflow() throws {
        let result = try XCTUnwrap(MemoryCalculator.calculate(pages(anonymous: 20, purgeable: 50)))
        XCTAssertEqual(result.usedBytes, 180 * 16_384)
    }

    func testInvalidAndOverflowingSnapshotsAreUnavailable() {
        XCTAssertNil(MemoryCalculator.calculate(pages(pageSize: 0)))
        XCTAssertNil(MemoryCalculator.calculate(pages(total: 0)))
        XCTAssertNil(MemoryCalculator.calculate(pages(total: 100)))
        XCTAssertNil(MemoryCalculator.calculate(pages(anonymous: .max, purgeable: 0)))
        XCTAssertNil(MemoryCalculator.calculate(pages(pageSize: .max)))
        XCTAssertNil(MemoryCalculator.calculate(pages(fileBacked: .max)))
    }

    func testUsedAndTotalMemoryUseTheSameBinaryScale() throws {
        let result = try XCTUnwrap(MemoryCalculator.calculate(pages(
            anonymous: 65_536, purgeable: 0, wired: 0, compressed: 0,
            fileBacked: 0, pageSize: 16_384, total: 8_589_934_592)))
        XCTAssertEqual(result.usedGB, 1)
        XCTAssertEqual(result.totalGB, 8)
        XCTAssertEqual(result.percentage, 12.5)
    }

    func testPhysicalRAMCapacityDisplaysSixteenInsteadOfSeventeenPointTwo() throws {
        let result = try XCTUnwrap(MemoryCalculator.calculate(pages(
            anonymous: 524_288, purgeable: 0, wired: 0, compressed: 0,
            fileBacked: 0, pageSize: 16_384, total: 17_179_869_184)))
        XCTAssertEqual(result.totalGB, 16)
        XCTAssertEqual(result.usedGB, 8)
        XCTAssertEqual(result.percentage, 50)
    }
}

final class HistoryAndPressureTests: XCTestCase {
    private func sample(at timestamp: Double, missing: Bool = false) -> SystemSample {
        SystemSample(timestamp: timestamp,
                     cpu: CPUReading(percentage: missing ? nil : 25, status: missing ? .unavailable : .valid),
                     memory: nil, pressure: .unavailable, pressureSource: .unavailable)
    }

    func testHistoryUsesSixtySecondsAtEveryRefreshInterval() {
        for interval in [1.0, 2.0, 5.0] {
            var history = SampleHistory()
            for timestamp in stride(from: 0.0, through: 120.0, by: interval) {
                history.append(sample(at: timestamp))
            }
            XCTAssertEqual(history.samples.first?.timestamp, 60)
            XCTAssertEqual(history.samples.last?.timestamp, 120)
            XCTAssertEqual(history.samples.count, Int(60 / interval) + 1)
        }
    }

    func testChangingIntervalKeepsTimestampSpacing() {
        var history = SampleHistory()
        for timestamp in [0.0, 1, 2, 4, 6, 11, 16, 21, 62] {
            history.append(sample(at: timestamp))
        }
        XCTAssertEqual(history.samples.map(\.timestamp), [2, 4, 6, 11, 16, 21, 62])
        XCTAssertEqual(history.visible(at: 66).map(\.timestamp), [6, 11, 16, 21, 62])
    }

    func testWakePrunesOldHistoryAndKeepsMissingSamplesAsGaps() {
        var history = SampleHistory()
        history.append(sample(at: 1))
        history.append(sample(at: 3, missing: true))
        XCTAssertNil(history.samples.last?.cpu.percentage)
        history.append(sample(at: 200, missing: true))
        XCTAssertEqual(history.samples.count, 1)
        XCTAssertTrue(history.visible(at: 261).isEmpty)
    }

    func testHistoryRejectsNonfiniteDuplicateAndOutOfOrderSamples() {
        var history = SampleHistory()
        history.append(sample(at: 2))
        history.append(sample(at: 2))
        history.append(sample(at: 1))
        history.append(sample(at: .infinity))
        history.append(sample(at: .nan))
        XCTAssertEqual(history.samples.count, 1)
    }

    func testPressureAcceptsOnlyKnownSystemFlags() {
        XCTAssertEqual(MemoryPressure(dispatchFlags: 1), .normal)
        XCTAssertEqual(MemoryPressure(dispatchFlags: 2), .warning)
        XCTAssertEqual(MemoryPressure(dispatchFlags: 4), .critical)
        for flag in [UInt32(0), 3, 5, 8, .max] {
            XCTAssertEqual(MemoryPressure(dispatchFlags: flag), .unavailable)
        }
    }
}

