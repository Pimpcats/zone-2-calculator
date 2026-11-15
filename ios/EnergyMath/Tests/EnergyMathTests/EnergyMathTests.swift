import XCTest
@testable import EnergyMath

// Reference profile used throughout: 40 y, 67 in, 170 lb, treadmill at 3.4 mph / 3.5 %.
// Expected values were worked out by hand from the published equations, independently
// of the app code.
private let kg = 170 * 0.45359237          // 77.1107 kg
private let cm = 67 * 2.54                 // 170.18 cm
private let age = 40

final class TreadmillTests: XCTestCase {

    func testMphToMetersPerMinute() {
        XCTAssertEqual(Energy.metersPerMinPerMph, 1609.344 / 60, accuracy: 1e-9)
        XCTAssertEqual(3.4 * Energy.metersPerMinPerMph, 91.196, accuracy: 0.001)
    }

    func testGradeIsPercentNotFraction() {
        // 3.5 % must enter the equation as 0.035: 0.1·S + 1.8·S·0.035 + 3.5
        let s = 91.19616
        XCTAssertEqual(Energy.treadmillVO2(mph: 3.4, gradePct: 3.5), 0.1 * s + 1.8 * s * 0.035 + 3.5, accuracy: 1e-6)
        XCTAssertEqual(Energy.treadmillVO2(mph: 3.4, gradePct: 3.5), 18.365, accuracy: 0.001)
        // If 3.5 were used as a fraction the result would be absurd (~587).
        XCTAssertLessThan(Energy.treadmillVO2(mph: 3.4, gradePct: 3.5), 25)
    }

    func testFlatWalkAndStandingStill() {
        XCTAssertEqual(Energy.treadmillVO2(mph: 3.0, gradePct: 0), 0.1 * 80.4672 + 3.5, accuracy: 1e-6)
        XCTAssertEqual(Energy.treadmillVO2(mph: 0, gradePct: 10), 3.5, accuracy: 1e-9)   // resting
    }

    func testPublishedWorkedExample() {
        // Textbook example: 3.0 mph at 5 % → 18.8 ml/kg/min (5.4 METs).
        XCTAssertEqual(Energy.treadmillVO2(mph: 3.0, gradePct: 5), 18.8, accuracy: 0.05)
    }

    func testGaitSelection() {
        XCTAssertEqual(Energy.gait(mph: 2.5, jogging: true), .walk)    // too slow to count as a jog
        XCTAssertEqual(Energy.gait(mph: 3.0, jogging: true), .run)
        XCTAssertEqual(Energy.gait(mph: 3.4, jogging: false), .walk)
        XCTAssertEqual(Energy.gait(mph: 4.5, jogging: false), .walk)
        XCTAssertEqual(Energy.gait(mph: 4.5, jogging: true), .run)
        XCTAssertEqual(Energy.gait(mph: 4.99, jogging: false), .walk)
        XCTAssertEqual(Energy.gait(mph: 5.0, jogging: false), .run)    // always running from 5 mph
    }

    func testSlowJogUsesRunningEquation() {
        let s = 4.5 * 26.8224
        XCTAssertEqual(Energy.treadmillVO2(mph: 4.5, gradePct: 0, jogging: false), 0.1 * s + 3.5, accuracy: 1e-6)
        XCTAssertEqual(Energy.treadmillVO2(mph: 4.5, gradePct: 0, jogging: true), 0.2 * s + 3.5, accuracy: 1e-6)
        XCTAssertEqual(Energy.treadmillVO2(mph: 4.5, gradePct: 0, jogging: true), 27.640, accuracy: 0.001)
    }

    func testRunningEquation() {
        let s = 6.0 * 26.8224
        XCTAssertEqual(Energy.treadmillVO2(mph: 6, gradePct: 1), 0.2 * s + 0.9 * s * 0.01 + 3.5, accuracy: 1e-6)
        XCTAssertEqual(Energy.treadmillVO2(mph: 6, gradePct: 1), 37.135, accuracy: 0.001)
    }

    func testGrossAndActiveForReferenceWorkout() {
        let perMin = Energy.treadmillKcalPerMin(mph: 3.4, gradePct: 3.5, weightKg: kg)
        XCTAssertEqual(perMin, 7.081, accuracy: 0.001)
        let gross = perMin * 80
        XCTAssertEqual(gross, 566.5, accuracy: 0.1)
        let rest = Energy.restingKcalPerMin(weightKg: kg, heightCm: cm, age: age, isMale: true)
        XCTAssertEqual(Energy.activeKcal(gross: gross, restPerMin: rest, seconds: 80 * 60), 475.4, accuracy: 0.1)
    }

    func testAccumulatorMatchesClosedForm() {
        var t = TreadmillAccumulator()
        for _ in 0..<4800 { t.add(seconds: 1, mph: 3.4, gradePct: 3.5, jogging: false, weightKg: kg) }
        XCTAssertEqual(t.seconds, 4800, accuracy: 1e-6)
        XCTAssertEqual(t.grossKcal, 566.454, accuracy: 0.01)
        XCTAssertEqual(t.miles, 3.4 * 80 / 60, accuracy: 1e-6)
    }

    func testSpeedAndInclineChangesMidWorkout() {
        var t = TreadmillAccumulator()
        t.add(seconds: 600, mph: 3.0, gradePct: 0, jogging: false, weightKg: kg)     // warm-up
        t.add(seconds: 1800, mph: 3.4, gradePct: 3.5, jogging: false, weightKg: kg)
        t.add(seconds: 600, mph: 3.4, gradePct: 6.0, jogging: false, weightKg: kg)   // steeper
        t.add(seconds: 300, mph: 5.5, gradePct: 1.0, jogging: false, weightKg: kg)   // run
        let expected =
            10 * Energy.treadmillKcalPerMin(mph: 3.0, gradePct: 0, weightKg: kg) +
            30 * Energy.treadmillKcalPerMin(mph: 3.4, gradePct: 3.5, weightKg: kg) +
            10 * Energy.treadmillKcalPerMin(mph: 3.4, gradePct: 6.0, weightKg: kg) +
            5 * Energy.treadmillKcalPerMin(mph: 5.5, gradePct: 1.0, weightKg: kg)
        XCTAssertEqual(t.grossKcal, expected, accuracy: 1e-6)
        XCTAssertEqual(t.seconds, 3300, accuracy: 1e-9)
        // Each segment costs what its own settings say: steeper and faster cost more.
        XCTAssertGreaterThan(Energy.treadmillKcalPerMin(mph: 3.4, gradePct: 6, weightKg: kg),
                             Energy.treadmillKcalPerMin(mph: 3.4, gradePct: 3.5, weightKg: kg))
    }

    func testInvalidTreadmillSettings() {
        XCTAssertEqual(Energy.treadmillVO2(mph: -3, gradePct: 5), 3.5, accuracy: 1e-9)           // negative speed → still
        XCTAssertEqual(Energy.treadmillVO2(mph: 3, gradePct: -5), Energy.treadmillVO2(mph: 3, gradePct: 0), accuracy: 1e-9)
        XCTAssertEqual(Energy.treadmillVO2(mph: 3, gradePct: 900), Energy.treadmillVO2(mph: 3, gradePct: 40), accuracy: 1e-9)
        XCTAssertEqual(Energy.treadmillVO2(mph: .nan, gradePct: .nan), 3.5, accuracy: 1e-9)
        XCTAssertEqual(Energy.treadmillKcalPerMin(mph: 3.4, gradePct: 3.5, weightKg: 0), 0)
        XCTAssertEqual(Energy.treadmillKcalPerMin(mph: 3.4, gradePct: 3.5, weightKg: -80), 0)
        var t = TreadmillAccumulator()
        t.add(seconds: -5, mph: 3, gradePct: 0, jogging: false, weightKg: kg)
        t.add(seconds: .nan, mph: 3, gradePct: 0, jogging: false, weightKg: kg)
        XCTAssertEqual(t.grossKcal, 0); XCTAssertEqual(t.seconds, 0)
    }
}

final class KeytelAndRestingTests: XCTestCase {

    func testMaleCoefficientsAndUnits() {
        // kJ/min = −55.0969 + 0.6309·HR + 0.1988·kg + 0.2017·age, then ÷ 4.184 → kcal/min
        let kJ = -55.0969 + 0.6309 * 125 + 0.1988 * kg + 0.2017 * 40
        XCTAssertEqual(Energy.keytelKcalPerMin(bpm: 125, weightKg: kg, age: age, isMale: true), kJ / 4.184, accuracy: 1e-9)
    }

    func testFemaleCoefficients() {
        let kJ = -20.4022 + 0.4472 * 125 - 0.1263 * kg + 0.074 * 40
        XCTAssertEqual(Energy.keytelKcalPerMin(bpm: 125, weightKg: kg, age: age, isMale: false), kJ / 4.184, accuracy: 1e-9)
        XCTAssertEqual(Energy.keytelKcalPerMin(bpm: 125, weightKg: kg, age: age, isMale: false), 6.864, accuracy: 0.001)
    }

    func testReferenceHeartRateRange() {
        XCTAssertEqual(Energy.keytelKcalPerMin(bpm: 125, weightKg: kg, age: age, isMale: true), 11.272, accuracy: 0.001)
        XCTAssertEqual(Energy.keytelKcalPerMin(bpm: 132.5, weightKg: kg, age: age, isMale: true), 12.403, accuracy: 0.001)
        XCTAssertEqual(Energy.keytelKcalPerMin(bpm: 140, weightKg: kg, age: age, isMale: true), 13.534, accuracy: 0.001)
        // 80 minutes: 902–1083 kcal gross.
        XCTAssertEqual(80 * Energy.keytelKcalPerMin(bpm: 125, weightKg: kg, age: age, isMale: true), 901.8, accuracy: 0.1)
        XCTAssertEqual(80 * Energy.keytelKcalPerMin(bpm: 140, weightKg: kg, age: age, isMale: true), 1082.7, accuracy: 0.1)
    }

    func testEachBeatAddsTheHeartRateCoefficient() {
        let a = Energy.keytelKcalPerMin(bpm: 130, weightKg: kg, age: age, isMale: true)
        let b = Energy.keytelKcalPerMin(bpm: 131, weightKg: kg, age: age, isMale: true)
        XCTAssertEqual(b - a, 0.6309 / 4.184, accuracy: 1e-9)
    }

    func testNeverNegativeAndInvalidInputs() {
        XCTAssertEqual(Energy.keytelKcalPerMin(bpm: 40, weightKg: 50, age: 20, isMale: true), 0)   // raw value is negative
        XCTAssertEqual(Energy.keytelKcalPerMin(bpm: .nan, weightKg: .nan, age: -5, isMale: true), 0)
        XCTAssertGreaterThanOrEqual(Energy.keytelKcalPerMin(bpm: 0, weightKg: 0, age: 0, isMale: false), 0)
        XCTAssertTrue(Energy.keytelKcalPerMin(bpm: 130, weightKg: -10, age: 40, isMale: true).isFinite)
    }

    func testMifflinStJeor() {
        // men: 10·kg + 6.25·cm − 5·age + 5 ; women: … − 161
        XCTAssertEqual(Energy.restingKcalPerDay(weightKg: kg, heightCm: cm, age: age, isMale: true), 1639.7, accuracy: 0.1)
        XCTAssertEqual(Energy.restingKcalPerDay(weightKg: kg, heightCm: cm, age: age, isMale: false), 1473.7, accuracy: 0.1)
        XCTAssertEqual(Energy.restingKcalPerMin(weightKg: kg, heightCm: cm, age: age, isMale: true), 1.1387, accuracy: 0.0001)
        XCTAssertEqual(Energy.restingKcalPerDay(weightKg: 0, heightCm: 0, age: 90, isMale: false), 0)   // clamped
        XCTAssertEqual(Energy.restingKcalPerDay(weightKg: .nan, heightCm: .nan, age: 40, isMale: false), 0)
    }

    func testActiveIsGrossMinusRestingAndNeverNegative() {
        XCTAssertEqual(Energy.activeKcal(gross: 901.78, restPerMin: 1.1387, seconds: 4800), 901.78 - 91.096, accuracy: 0.01)
        XCTAssertEqual(Energy.activeKcal(gross: 10, restPerMin: 1.2, seconds: 3600), 0)
        XCTAssertEqual(Energy.activeKcal(gross: 100, restPerMin: -5, seconds: 600), 100)
        XCTAssertEqual(Energy.activeKcal(gross: .nan, restPerMin: 1, seconds: 60), 0)
    }

    func testTheTwoEstimatesStaySeparate() {
        // Different inputs entirely: changing heart rate must not move the treadmill
        // figure, and changing speed or grade must not move the heart-rate figure.
        let tm = Energy.treadmillKcalPerMin(mph: 3.4, gradePct: 3.5, weightKg: kg)
        let hr = Energy.keytelKcalPerMin(bpm: 132, weightKg: kg, age: age, isMale: true)
        XCTAssertNotEqual(tm, hr)
        XCTAssertGreaterThan(hr, tm * 1.5)   // documents the size of the disagreement for this profile
    }
}

final class HeartRateTimingTests: XCTestCase {

    func testSteadyOneHertzIsAllMeasured() {
        var h = HRAccumulator()
        h.begin(at: 0)
        for t in 1...600 { _ = h.add(bpm: 130, at: Double(t)) }
        XCTAssertEqual(h.measuredSeconds, 600, accuracy: 1e-9)
        XCTAssertEqual(h.interpolatedSeconds, 0)
        XCTAssertEqual(h.averageBpm, 130, accuracy: 1e-9)
        let c = h.coverage(duration: 600)
        XCTAssertEqual(c.measured, 1, accuracy: 1e-9); XCTAssertEqual(c.missing, 0, accuracy: 1e-9)
    }

    func testAverageIsTimeWeightedNotPerPacket() {
        // 100 s at 120 bpm arrives as 100 packets; 100 s at 160 bpm arrives as 400 packets.
        // A per-packet mean would say 152; the time-weighted mean is ~140.
        var h = HRAccumulator()
        h.begin(at: 0)
        for t in 1...100 { _ = h.add(bpm: 120, at: Double(t)) }
        for i in 1...400 { _ = h.add(bpm: 160, at: 100 + Double(i) * 0.25) }
        XCTAssertEqual(h.trackedSeconds, 200, accuracy: 1e-6)
        XCTAssertEqual(h.averageBpm, 140, accuracy: 0.1)
    }

    func testBurstOfLatePacketsDoesNotAddTime() {
        var h = HRAccumulator()
        h.begin(at: 0)
        _ = h.add(bpm: 130, at: 1)
        // Five queued notifications delivered within 20 ms after a 5 s stall.
        for i in 0..<5 { _ = h.add(bpm: 130, at: 6 + Double(i) * 0.004) }
        XCTAssertEqual(h.trackedSeconds, 6.016, accuracy: 1e-6)   // wall time, not 6 packets × 1 s
    }

    func testDuplicateTimestampAndClockGoingBackwards() {
        var h = HRAccumulator()
        h.begin(at: 100)
        XCTAssertNotNil(h.add(bpm: 130, at: 101))
        XCTAssertNil(h.add(bpm: 130, at: 101))     // same instant
        XCTAssertNil(h.add(bpm: 130, at: 95))      // clock stepped back
        XCTAssertEqual(h.trackedSeconds, 1, accuracy: 1e-9)
    }

    func testShortGapIsInterpolatedAndCountedSeparately() {
        var h = HRAccumulator()
        h.begin(at: 0)
        _ = h.add(bpm: 120, at: 1)
        let c = h.add(bpm: 140, at: 13)            // 12 s gap
        XCTAssertEqual(c, HRAccumulator.Credit(seconds: 12, bpm: 130, interpolated: true))
        XCTAssertEqual(h.measuredSeconds, 1, accuracy: 1e-9)
        XCTAssertEqual(h.interpolatedSeconds, 12, accuracy: 1e-9)
    }

    func testGapBoundaries() {
        var h = HRAccumulator()
        h.begin(at: 0)
        _ = h.add(bpm: 130, at: 1)
        XCTAssertEqual(h.add(bpm: 130, at: 4)?.interpolated, false)      // exactly 3 s: measured
        XCTAssertEqual(h.add(bpm: 130, at: 7.5)?.interpolated, true)     // 3.5 s: interpolated
        XCTAssertNotNil(h.add(bpm: 130, at: 37.5))                       // exactly 30 s: bridged
        XCTAssertNil(h.add(bpm: 130, at: 67.6))                          // 30.1 s: dropout
    }

    func testDropoutIsCreditedNothing() {
        var h = HRAccumulator()
        h.begin(at: 0)
        for t in 1...60 { _ = h.add(bpm: 130, at: Double(t)) }
        XCTAssertNil(h.add(bpm: 135, at: 300))                 // 4-minute dropout
        for t in 301...360 { _ = h.add(bpm: 135, at: Double(t)) }
        XCTAssertEqual(h.trackedSeconds, 120, accuracy: 1e-9)  // the 240 s gap is not counted
        let c = h.coverage(duration: 360)
        XCTAssertEqual(c.measured, 120.0 / 360, accuracy: 1e-9)
        XCTAssertEqual(c.interpolated, 0, accuracy: 1e-9)
        XCTAssertEqual(c.missing, 240.0 / 360, accuracy: 1e-9)
    }

    func testMissingDataCannotInflateCalories() {
        // Same workout with and without a dropout: the one with missing data must come
        // out lower, by exactly the missing time's share — never higher.
        func kcal(dropout: Bool) -> Double {
            var h = HRAccumulator(); var total = 0.0
            h.begin(at: 0)
            for t in 1...1200 where !(dropout && (301...900).contains(t)) {
                if let c = h.add(bpm: 130, at: Double(t)) {
                    total += Energy.keytelKcalPerMin(bpm: c.bpm, weightKg: kg, age: age, isMale: true) * c.seconds / 60
                }
            }
            return total
        }
        let full = kcal(dropout: false), gappy = kcal(dropout: true)
        XCTAssertEqual(full, 20 * 12.0262, accuracy: 0.01)
        XCTAssertEqual(gappy, full * 599 / 1200, accuracy: 0.01)   // 601 s dropped (300→901)
        XCTAssertLessThan(gappy, full)
    }

    func testStrapConnectedLateAfterStart() {
        var h = HRAccumulator()
        h.begin(at: 0)
        XCTAssertNil(h.add(bpm: 110, at: 120))      // first reading 2 min in: nothing credited
        _ = h.add(bpm: 110, at: 121)
        XCTAssertEqual(h.trackedSeconds, 1, accuracy: 1e-9)
        var g = HRAccumulator()
        g.begin(at: 0)
        XCTAssertEqual(g.add(bpm: 110, at: 10)?.interpolated, true)   // short wait: filled in, flagged
    }

    func testPausedTimeIsNotCounted() {
        var h = HRAccumulator()
        XCTAssertNil(h.add(bpm: 130, at: 5))        // never started
        h.begin(at: 10)
        _ = h.add(bpm: 130, at: 11)
        h.pause()
        XCTAssertNil(h.add(bpm: 130, at: 12))       // paused: readings ignored
        XCTAssertNil(h.add(bpm: 130, at: 20))
        h.begin(at: 500)                            // resume much later
        _ = h.add(bpm: 130, at: 501)
        XCTAssertEqual(h.trackedSeconds, 2, accuracy: 1e-9)
    }

    func testImplausibleReadingsAreIgnored() {
        var h = HRAccumulator()
        h.begin(at: 0)
        XCTAssertNil(h.add(bpm: 0, at: 1))
        XCTAssertNil(h.add(bpm: -20, at: 2))
        XCTAssertNil(h.add(bpm: 400, at: 3))
        XCTAssertNil(h.add(bpm: 130, at: .nan))
        XCTAssertEqual(h.trackedSeconds, 0)
        XCTAssertEqual(h.averageBpm, 0)             // no divide-by-zero
        XCTAssertNotNil(h.add(bpm: 130, at: 3.5))   // bad packets didn't reset the clock
        XCTAssertEqual(h.trackedSeconds, 3.5, accuracy: 1e-9)
    }

    func testCoverageSharesAlwaysSumToOne() {
        var h = HRAccumulator()
        h.begin(at: 0)
        _ = h.add(bpm: 130, at: 1); _ = h.add(bpm: 130, at: 11); _ = h.add(bpm: 130, at: 12)
        for d in [0.0, 5, 12, 12.4, 100] {
            let c = h.coverage(duration: d)
            XCTAssertEqual(c.measured + c.interpolated + c.missing, 1, accuracy: 1e-9)
            XCTAssertGreaterThanOrEqual(c.missing, 0)
        }
    }
}

final class WeightTrendTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func day(_ d: Double) -> Date { now.addingTimeInterval(-d * 86400) }
    /// Weigh-ins on the given days-ago, on a perfect line losing `perWeek` lbs a week.
    private func line(_ daysAgo: [Double], perWeek: Double = 1, end: Double = 170) -> [WeightEntry] {
        daysAgo.map { WeightEntry(date: day($0), lbs: end + perWeek * $0 / 7) }
    }

    func testSteadyLossOverFourWeeks() throws {
        let t = try XCTUnwrap(Energy.trend(line([28, 21, 14, 7, 0]), now: now))
        XCTAssertEqual(t.lbsPerWeek, -1, accuracy: 1e-9)
        XCTAssertEqual(t.deficitPerDay, 500, accuracy: 1e-6)     // 1 lb/week ≈ 3500 ÷ 7
        XCTAssertEqual(t.spanDays, 28, accuracy: 1e-9)
        XCTAssertFalse(t.preliminary); XCTAssertTrue(t.preferredLength)
    }

    func testMissingWeighInsDoNotDistortTheSlope() throws {
        // Very irregular logging on the same underlying line.
        let t = try XCTUnwrap(Energy.trend(line([27, 26, 25, 9, 1, 0]), now: now))
        XCTAssertEqual(t.lbsPerWeek, -1, accuracy: 1e-9)
    }

    func testTooFewWeighInsOrTooShortGivesNoTrend() {
        XCTAssertNil(Energy.trend([], now: now))
        XCTAssertNil(Energy.trend(line([20, 10, 0]), now: now))             // 3 weigh-ins
        XCTAssertNil(Energy.trend(line([13, 9, 5, 2, 0]), now: now))        // only 13 days
        XCTAssertNil(Energy.trend(line([3, 3, 3, 3]), now: now))            // all the same day
    }

    func testShortTrendIsPreliminaryAndNeverCompared() throws {
        let t = try XCTUnwrap(Energy.trend(line([16, 12, 6, 0]), now: now))
        XCTAssertTrue(t.preliminary)
        XCTAssertNil(Energy.impliedBurn(intakeKcalPerDay: 2200, trend: t))
    }

    func testThreeWeeksIsUsableButNotPreferred() throws {
        let t = try XCTUnwrap(Energy.trend(line([21, 14, 7, 0]), now: now))
        XCTAssertFalse(t.preliminary); XCTAssertFalse(t.preferredLength)
        XCTAssertEqual(try XCTUnwrap(Energy.impliedBurn(intakeKcalPerDay: 2200, trend: t)), 2700, accuracy: 1e-6)
    }

    func testMissingIntakeIsUnknownNotZero() throws {
        let t = try XCTUnwrap(Energy.trend(line([28, 21, 14, 7, 0]), now: now))
        XCTAssertNil(Energy.validIntake(0))
        XCTAssertNil(Energy.validIntake(-100))
        XCTAssertNil(Energy.validIntake(120))         // implausible → unknown
        XCTAssertNil(Energy.validIntake(50_000))
        XCTAssertEqual(Energy.validIntake(2200), 2200)
        // With intake unknown there is no implied burn at all — in particular not 0 + 500.
        XCTAssertNil(Energy.impliedBurn(intakeKcalPerDay: 0, trend: t))
    }

    func testOldWeighInsFallOutsideTheWindow() {
        XCTAssertNil(Energy.trend(line([120, 110, 100, 90]), now: now))
        // Old entries are ignored; the recent ones alone aren't enough.
        XCTAssertNil(Energy.trend(line([120, 110, 100, 5, 0]), now: now))
    }

    func testInvalidWeighInsAreIgnored() throws {
        var w = line([28, 21, 14, 7, 0])
        w.append(WeightEntry(date: day(10), lbs: .nan))
        w.append(WeightEntry(date: day(11), lbs: 0))
        w.append(WeightEntry(date: day(-3), lbs: 300))      // dated in the future
        let t = try XCTUnwrap(Energy.trend(w, now: now))
        XCTAssertEqual(t.entries, 5)
        XCTAssertEqual(t.lbsPerWeek, -1, accuracy: 1e-9)
    }

    func testGainIsASurplus() throws {
        let t = try XCTUnwrap(Energy.trend(line([28, 21, 14, 7, 0], perWeek: -0.5), now: now))
        XCTAssertEqual(t.lbsPerWeek, 0.5, accuracy: 1e-9)
        XCTAssertEqual(t.deficitPerDay, -250, accuracy: 1e-6)
    }

    func testComparisonThreshold() {
        XCTAssertEqual(Energy.compare(estimated: 2700, implied: 2600), .consistent)     // within 10 %
        XCTAssertEqual(Energy.compare(estimated: 3000, implied: 2600), .estimateHigh)
        XCTAssertEqual(Energy.compare(estimated: 2200, implied: 2600), .estimateLow)
        XCTAssertEqual(Energy.compare(estimated: 2200, implied: 0), .consistent)        // nothing to compare against
    }
}
