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

final class ApplicationUsageTests: XCTestCase {
    private func process(_ pid: Int32 = 1, app: String = "Editor", ticks: UInt64 = 100,
                         memory: UInt64 = 100, start: UInt64 = 1,
                         at timestamp: Double = 1) -> ProcessResourceSample {
        ProcessResourceSample(pid: pid, startTime: start, appID: "/\(app).app",
                              appName: app, cpuTicks: ticks, memoryBytes: memory,
                              timestamp: timestamp)
    }

    func testFirstSampleHasMemoryButNoInventedCPU() throws {
        var calculator = ApplicationUsageCalculator()
        let snapshot = calculator.consume([process()], secondsPerTick: 1, processorCount: 8,
                                          maximumGap: 15)
        let app = try XCTUnwrap(snapshot.applications.first)
        XCTAssertNil(app.cpuPercentage)
        XCTAssertEqual(app.memoryBytes, 100)
        XCTAssertTrue(snapshot.topFive(by: .cpu).isEmpty)
        XCTAssertEqual(snapshot.topFive(by: .memory).count, 1)
    }

    func testHelpersAreAggregatedAndCPUNormalizedToWholeMachine() throws {
        var calculator = ApplicationUsageCalculator()
        _ = calculator.consume([process(), process(2)], secondsPerTick: 0.001,
                               processorCount: 8, maximumGap: 15)
        let snapshot = calculator.consume([process(ticks: 2100, memory: 500, at: 3),
                                          process(2, ticks: 4100, memory: 200, at: 3)],
                                         secondsPerTick: 0.001, processorCount: 8, maximumGap: 15)
        let app = try XCTUnwrap(snapshot.applications.first)
        XCTAssertEqual(snapshot.applications.count, 1)
        XCTAssertEqual(try XCTUnwrap(app.cpuPercentage), 37.5, accuracy: 0.0001)
        XCTAssertEqual(app.memoryBytes, 700)
        XCTAssertEqual(app.processCount, 2)
    }

    func testAppleSiliconMachTimebaseIsApplied() throws {
        var calculator = ApplicationUsageCalculator()
        let scale = 125.0 / 3.0 / 1_000_000_000
        _ = calculator.consume([process(ticks: 0)], secondsPerTick: scale,
                               processorCount: 8, maximumGap: 15)
        let result = calculator.consume([process(ticks: 48_000_000, at: 3)],
                                        secondsPerTick: scale, processorCount: 8, maximumGap: 15)
        XCTAssertEqual(try XCTUnwrap(result.applications.first?.cpuPercentage), 12.5,
                       accuracy: 0.0001)
    }

    func testReusedPIDOrChangedApplicationRequiresNewBaseline() throws {
        for sample in [process(ticks: 500, start: 2, at: 3),
                       process(app: "Browser", ticks: 500, at: 3)] {
            var calculator = ApplicationUsageCalculator()
            _ = calculator.consume([process()], secondsPerTick: 1, processorCount: 8, maximumGap: 15)
            let snapshot = calculator.consume([sample], secondsPerTick: 1,
                                               processorCount: 8, maximumGap: 15)
            XCTAssertNil(try XCTUnwrap(snapshot.applications.first).cpuPercentage)
        }
    }

    func testInvalidIntervalsAndCountersDoNotProduceCPUValues() throws {
        for sample in [process(ticks: 99, at: 3), process(at: 1),
                       process(at: 0), process(at: 100)] {
            var calculator = ApplicationUsageCalculator()
            _ = calculator.consume([process()], secondsPerTick: 1, processorCount: 8, maximumGap: 15)
            let snapshot = calculator.consume([sample], secondsPerTick: 1,
                                               processorCount: 8, maximumGap: 15)
            XCTAssertNil(try XCTUnwrap(snapshot.applications.first).cpuPercentage)
        }
        var calculator = ApplicationUsageCalculator()
        XCTAssertTrue(calculator.consume([process(at: .nan)], secondsPerTick: 1,
                                         processorCount: 8, maximumGap: 15).applications.isEmpty)
    }

    func testPanelResetAndMissingProcessesDiscardOldCounters() throws {
        var calculator = ApplicationUsageCalculator()
        _ = calculator.consume([process()], secondsPerTick: 1, processorCount: 8, maximumGap: 15)
        let empty = calculator.consume([], secondsPerTick: 1, processorCount: 8, maximumGap: 15)
        XCTAssertTrue(empty.applications.isEmpty)
        let returned = calculator.consume([process(at: 3)], secondsPerTick: 1,
                                           processorCount: 8, maximumGap: 15)
        XCTAssertNil(try XCTUnwrap(returned.applications.first).cpuPercentage)
        calculator.reset()
        let reopened = calculator.consume([process(at: 5)], secondsPerTick: 1,
                                           processorCount: 8, maximumGap: 15)
        XCTAssertNil(try XCTUnwrap(reopened.applications.first).cpuPercentage)
    }

    func testRankingsHaveIndependentTopFivesAndStableTies() {
        let apps = (1...7).map { index in
            ApplicationUsage(id: "\(index)", name: "App \(index)",
                             cpuPercentage: Double(index), memoryBytes: UInt64(8 - index),
                             processCount: 1)
        }
        let snapshot = ApplicationUsageSnapshot(applications: apps, unreadableProcesses: 1)
        XCTAssertEqual(snapshot.topFive(by: .cpu).map(\.id), ["7", "6", "5", "4", "3"])
        XCTAssertEqual(snapshot.topFive(by: .memory).map(\.id), ["1", "2", "3", "4", "5"])
        let ties = ApplicationUsageSnapshot(applications: [
            ApplicationUsage(id: "b", name: "Same", cpuPercentage: 0, memoryBytes: 0, processCount: 1),
            ApplicationUsage(id: "a", name: "Same", cpuPercentage: 0, memoryBytes: 0, processCount: 1)
        ], unreadableProcesses: 0)
        XCTAssertEqual(ties.topFive(by: .cpu).map(\.id), ["a", "b"])
    }

    func testOverflowIsUnavailableAndNewHelperDoesNotInventCPU() throws {
        var calculator = ApplicationUsageCalculator()
        _ = calculator.consume([process()], secondsPerTick: 1, processorCount: 1, maximumGap: 15)
        let snapshot = calculator.consume([process(ticks: 200, memory: .max, at: 3),
                                          process(2, memory: 1, at: 3)],
                                         secondsPerTick: 1, processorCount: 1, maximumGap: 15)
        let app = try XCTUnwrap(snapshot.applications.first)
        XCTAssertNil(app.memoryBytes)
        XCTAssertNil(app.cpuPercentage)
    }
}

final class TemperatureSelectionTests: XCTestCase {
    func testChoosesChipHotspotAcrossPMUsInsteadOfOtherSensorTypes() throws {
        let result = try XCTUnwrap(TemperatureSelection.reading(from: [
            TemperatureSensorValue(name: "PMU tdie1", celsius: 42),
            TemperatureSensorValue(name: "PMU2 tdie8", celsius: 56.5),
            TemperatureSensorValue(name: "PMU tcal", celsius: 80),
            TemperatureSensorValue(name: "gas gauge battery", celsius: 90)
        ]))
        XCTAssertEqual(result.celsius, 56.5)
        XCTAssertEqual(result.sensorName, "PMU2 tdie8")
        XCTAssertEqual(result.source, .chipHotspot)
    }

    func testCalibratedPMUFallbackIsLabelledSeparately() throws {
        let result = try XCTUnwrap(TemperatureSelection.reading(from: [
            TemperatureSensorValue(name: "PMU tcal", celsius: 38),
            TemperatureSensorValue(name: "PMU2 tcal", celsius: 40)
        ]))
        XCTAssertEqual(result.celsius, 40)
        XCTAssertEqual(result.source, .calibratedPMU)
        XCTAssertEqual(result.source.title, "PMU sıcaklık sensörü")
    }

    func testInvalidTemperaturesAreUnavailableRatherThanClamped() {
        for value in [0.0, -10, 150, 1000, .nan, .infinity, -.infinity] {
            XCTAssertNil(TemperatureSelection.reading(from: [
                TemperatureSensorValue(name: "PMU tdie1", celsius: value)
            ]))
        }
    }

    func testBatteryAmbientAndUnidentifiedSensorsAreNotChipReadings() {
        let samples = ["gas gauge battery", "Ambient", "PMU tdev1", "Unknown", "PMU tdie1 extra"]
            .map { TemperatureSensorValue(name: $0, celsius: 45) }
        XCTAssertNil(TemperatureSelection.reading(from: samples))
        XCTAssertNil(TemperatureSelection.reading(from: []))
    }

    func testInvalidChipReadingsDoNotHideValidFallback() throws {
        let result = try XCTUnwrap(TemperatureSelection.reading(from: [
            TemperatureSensorValue(name: "PMU tdie1", celsius: .nan),
            TemperatureSensorValue(name: "PMU tcal", celsius: 37.25)
        ]))
        XCTAssertEqual(result.source, .calibratedPMU)
        XCTAssertEqual(result.celsius, 37.25)
    }

    func testTiedSensorsHaveDeterministicSourceNames() throws {
        let result = try XCTUnwrap(TemperatureSelection.reading(from: [
            TemperatureSensorValue(name: "PMU tdie2", celsius: 50),
            TemperatureSensorValue(name: "PMU tdie1", celsius: 50)
        ]))
        XCTAssertEqual(result.sensorName, "PMU tdie1")
    }

    func testMissingReadingDoesNotReusePriorTemperature() {
        XCTAssertNotNil(TemperatureSelection.reading(from: [
            TemperatureSensorValue(name: "PMU tdie1", celsius: 50)
        ]))
        XCTAssertNil(TemperatureSelection.reading(from: []))
        let sleeping = SystemSample(timestamp: 10, cpu: CPUReading(percentage: nil, status: .sleeping),
                                    memory: nil, pressure: .unavailable, pressureSource: .unavailable)
        XCTAssertNil(sleeping.temperature)
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

