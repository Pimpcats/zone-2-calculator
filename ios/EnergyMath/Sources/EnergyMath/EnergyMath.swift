import Foundation

// Pure calculation code for every calorie / energy figure in the app. Foundation only,
// no UI, so it is unit-tested on its own (see ios/EnergyMath/Package.swift).
//
// Everything here comes from population equations. The results are estimates — they are
// not measurements and have not been clinically validated for any individual.

enum Energy {

    // MARK: Units

    static let kgPerLb = 0.45359237
    static let cmPerInch = 2.54
    static let metersPerMinPerMph = 26.8224     // 1609.344 m ÷ 60 min
    static let kJPerKcal = 4.184

    /// A usable number, or `fallback` for NaN / infinity.
    private static func finite(_ v: Double, _ fallback: Double = 0) -> Double { v.isFinite ? v : fallback }

    // MARK: Heart-rate estimate (Keytel et al., J Sports Sci 2005;23(3):289–97)

    /// Gross kcal/min from heart rate, without a VO2max term. The published equation gives
    /// kJ/min from HR (bpm), weight (kg) and age (years); dividing by 4.184 gives kcal.
    /// It was fitted to moderate-to-hard exercise and over-reads at low heart rates.
    /// Never negative.
    static func keytelKcalPerMin(bpm: Double, weightKg: Double, age: Int, isMale: Bool) -> Double {
        let hr = finite(bpm), w = max(0, finite(weightKg)), a = Double(max(0, age))
        let kJ = isMale
            ? -55.0969 + 0.6309 * hr + 0.1988 * w + 0.2017 * a
            : -20.4022 + 0.4472 * hr - 0.1263 * w + 0.0740 * a
        return max(0, kJ / kJPerKcal)
    }

    // MARK: Resting expenditure (Mifflin–St Jeor, 1990)

    static func restingKcalPerDay(weightKg: Double, heightCm: Double, age: Int, isMale: Bool) -> Double {
        let w = max(0, finite(weightKg)), h = max(0, finite(heightCm))
        return max(0, 10 * w + 6.25 * h - 5 * Double(max(0, age)) + (isMale ? 5 : -161))
    }

    static func restingKcalPerMin(weightKg: Double, heightCm: Double, age: Int, isMale: Bool) -> Double {
        restingKcalPerDay(weightKg: weightKg, heightCm: heightCm, age: age, isMale: isMale) / 1440
    }

    /// Gross minus the resting share for the same stretch of time. Never negative.
    static func activeKcal(gross: Double, restPerMin: Double, seconds: Double) -> Double {
        max(0, finite(gross) - max(0, finite(restPerMin)) * max(0, finite(seconds)) / 60)
    }

    // MARK: Treadmill estimate (ACSM metabolic equations)

    enum Gait { case walk, run }

    static let jogMinMph = 3.0    // slowest speed the running equation applies to, if jogging
    static let runMinMph = 5.0    // at or above this, always the running equation
    static let maxGradePct = 40.0

    /// Which ACSM equation applies. Speed alone can't tell a fast walk from a slow jog, so
    /// between 3 and 5 mph it follows what the user says they're doing.
    static func gait(mph: Double, jogging: Bool) -> Gait {
        if mph >= runMinMph { return .run }
        if mph >= jogMinMph && jogging { return .run }
        return .walk
    }

    /// Gross oxygen cost in ml/kg/min. S is speed in m/min and G the grade as a fraction
    /// (3.5 % → 0.035):  walking 0.1·S + 1.8·S·G + 3.5,  running 0.2·S + 0.9·S·G + 3.5.
    /// Standing still (speed 0) is the resting 3.5.
    static func treadmillVO2(mph: Double, gradePct: Double, jogging: Bool = false) -> Double {
        let speed = max(0, finite(mph))
        let s = speed * metersPerMinPerMph
        let g = min(max(0, finite(gradePct)), maxGradePct) / 100
        switch gait(mph: speed, jogging: jogging) {
        case .walk: return 0.1 * s + 1.8 * s * g + 3.5
        case .run:  return 0.2 * s + 0.9 * s * g + 3.5
        }
    }

    /// Gross kcal/min on a treadmill (1 L of oxygen ≈ 5 kcal → ml/kg/min × kg ÷ 200).
    static func treadmillKcalPerMin(mph: Double, gradePct: Double, weightKg: Double,
                                    jogging: Bool = false) -> Double {
        treadmillVO2(mph: mph, gradePct: gradePct, jogging: jogging) * max(0, finite(weightKg)) / 200
    }

    // MARK: Body-weight trend

    static let kcalPerLb = 3500.0       // rule-of-thumb energy content of a pound of body mass
    static let sedentaryFactor = 1.2    // resting → non-exercise daily expenditure
    static let trendWindowDays = 56.0
    static let trendMinEntries = 4
    static let trendMinDays = 14.0          // below this no trend is shown at all
    static let trendMeaningfulDays = 21.0   // below this it is "preliminary": no comparison
    static let trendPreferredDays = 28.0

    struct Trend: Equatable {
        var entries: Int
        var start: Date
        var end: Date
        var lbsPerWeek: Double          // negative = losing

        var spanDays: Double { end.timeIntervalSince(start) / 86400 }
        /// Average daily energy balance implied by the trend; positive = deficit.
        var deficitPerDay: Double { -lbsPerWeek / 7 * Energy.kcalPerLb }
        /// Under three weeks: mostly water-weight noise, so it is shown but never compared.
        var preliminary: Bool { spanDays < Energy.trendMeaningfulDays }
        var preferredLength: Bool { spanDays >= Energy.trendPreferredDays }
    }

    /// Least-squares slope through the weigh-ins inside the window. Weigh-ins can be
    /// irregular — each one is placed at its real date, so skipped days don't distort the
    /// slope. Returns nil with fewer than 4 weigh-ins or less than 14 days between the
    /// first and last.
    static func trend(_ all: [WeightEntry], windowDays: Double = trendWindowDays, now: Date = Date()) -> Trend? {
        let cutoff = now.addingTimeInterval(-windowDays * 86400)
        let pts = all.filter { $0.date >= cutoff && $0.date <= now && $0.lbs.isFinite && $0.lbs > 0 }
            .sorted { $0.date < $1.date }
        guard pts.count >= trendMinEntries, let first = pts.first, let last = pts.last else { return nil }
        guard last.date.timeIntervalSince(first.date) / 86400 >= trendMinDays else { return nil }
        let xs = pts.map { $0.date.timeIntervalSince(first.date) / 86400 }
        let ys = pts.map { $0.lbs }
        let n = Double(pts.count)
        let mx = xs.reduce(0, +) / n, my = ys.reduce(0, +) / n
        var sxy = 0.0, sxx = 0.0
        for i in pts.indices { sxy += (xs[i] - mx) * (ys[i] - my); sxx += (xs[i] - mx) * (xs[i] - mx) }
        guard sxx > 0 else { return nil }
        return Trend(entries: pts.count, start: first.date, end: last.date, lbsPerWeek: sxy / sxx * 7)
    }

    /// The user's average daily intake, or nil when it hasn't been entered. A blank or
    /// implausible value is "unknown" — it is never treated as zero calories eaten.
    static func validIntake(_ kcalPerDay: Int) -> Double? {
        (500...10000).contains(kcalPerDay) ? Double(kcalPerDay) : nil
    }

    /// Daily expenditure implied by intake plus the trend's deficit. Nil when intake is
    /// unknown or the trend is still preliminary.
    static func impliedBurn(intakeKcalPerDay: Int, trend: Trend) -> Double? {
        guard !trend.preliminary, let intake = validIntake(intakeKcalPerDay) else { return nil }
        return intake + trend.deficitPerDay
    }

    enum Agreement: Equatable { case consistent, estimateHigh, estimateLow }

    /// Within 10 % counts as agreement — the inputs aren't precise enough for more.
    static func compare(estimated: Double, implied: Double) -> Agreement {
        guard implied > 0, abs(estimated - implied) > 0.10 * implied else { return .consistent }
        return estimated > implied ? .estimateHigh : .estimateLow
    }
}

/// One body-weight weigh-in.
struct WeightEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var date: Date
    var lbs: Double
}

/// Turns a stream of heart-rate readings with irregular timing into time-weighted totals.
///
/// A strap normally notifies about once a second, but Bluetooth delivers late, in bursts,
/// or not at all. Each reading is credited with the real time since the previous one:
///  - up to `measuredMaxGap` apart → **measured** time
///  - up to `bridgeMaxGap` apart   → **interpolated** time (mean of the two readings)
///  - longer than that             → a dropout: credited nothing, so missing data can
///    neither add calories nor vanish silently — it shows up as lost coverage.
struct HRAccumulator {
    static let measuredMaxGap = 3.0
    static let bridgeMaxGap = 30.0
    static let validBpm = 25...250

    /// What one reading contributed.
    struct Credit: Equatable {
        var seconds: Double
        var bpm: Double            // mean heart rate over those seconds
        var interpolated: Bool
    }

    private(set) var measuredSeconds = 0.0
    private(set) var interpolatedSeconds = 0.0
    private(set) var bpmSeconds = 0.0          // Σ bpm × seconds
    private var lastTime: Double?
    private var lastBpm: Int?

    var trackedSeconds: Double { measuredSeconds + interpolatedSeconds }
    /// Time-weighted mean heart rate (0 when nothing has been credited).
    var averageBpm: Double { trackedSeconds > 0 ? bpmSeconds / trackedSeconds : 0 }

    /// Workout started or resumed at `time`: the clock runs from here, with no reading yet.
    mutating func begin(at time: Double) { lastTime = time; lastBpm = nil }

    /// Workout paused: time until the next `begin` is not workout time.
    mutating func pause() { lastTime = nil; lastBpm = nil }

    /// Feed one reading taken at `time` (seconds on any steadily increasing clock).
    /// Returns what it was credited, or nil if it was credited nothing.
    mutating func add(bpm: Int, at time: Double) -> Credit? {
        guard HRAccumulator.validBpm.contains(bpm), time.isFinite else { return nil }
        defer { if lastTime != nil { lastTime = time; lastBpm = bpm } }
        guard let last = lastTime else { return nil }            // not running
        let dt = time - last
        guard dt > 0, dt <= HRAccumulator.bridgeMaxGap else { return nil }
        // Normal cadence with a previous reading is measured; a longer gap, or the stretch
        // between Start and a late first reading, is filled in rather than observed.
        let interpolated = dt > HRAccumulator.measuredMaxGap
        let mean = lastBpm.map { (Double($0) + Double(bpm)) / 2 } ?? Double(bpm)
        if interpolated { interpolatedSeconds += dt } else { measuredSeconds += dt }
        bpmSeconds += mean * dt
        return Credit(seconds: dt, bpm: mean, interpolated: interpolated)
    }

    /// Split a workout of `duration` seconds into measured / interpolated / missing shares.
    func coverage(duration: Double) -> (measured: Double, interpolated: Double, missing: Double) {
        guard duration > 0 else { return (1, 0, 0) }
        let m = min(1, measuredSeconds / duration)
        let i = min(1 - m, interpolatedSeconds / duration)
        return (m, i, max(0, 1 - m - i))
    }
}

/// Integrates the treadmill estimate over time so speed, incline or gait changes made
/// mid-workout each apply only from the moment they're made.
struct TreadmillAccumulator {
    private(set) var grossKcal = 0.0
    private(set) var seconds = 0.0
    private(set) var miles = 0.0

    mutating func add(seconds dt: Double, mph: Double, gradePct: Double, jogging: Bool, weightKg: Double) {
        guard dt.isFinite, dt > 0 else { return }
        grossKcal += Energy.treadmillKcalPerMin(mph: mph, gradePct: gradePct, weightKg: weightKg,
                                                jogging: jogging) * dt / 60
        miles += max(0, mph.isFinite ? mph : 0) * dt / 3600
        seconds += dt
    }
}
