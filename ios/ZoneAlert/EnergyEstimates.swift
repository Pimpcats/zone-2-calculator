import Foundation
import SwiftUI

/// Energy-expenditure estimates that sit alongside the heart-rate (Keytel) figure, so the
/// app can compare independent estimates instead of trusting one. Everything here is an
/// approximation from population equations — none of it is a measurement.
enum Energy {

    // MARK: Resting expenditure

    /// Resting metabolic rate in kcal/day (Mifflin–St Jeor, 1990).
    static func restingKcalPerDay(weightKg: Double, heightCm: Double, age: Int, isMale: Bool) -> Double {
        max(0, 10 * weightKg + 6.25 * heightCm - 5 * Double(age) + (isMale ? 5 : -161))
    }

    static func restingKcalPerMin(weightKg: Double, heightCm: Double, age: Int, isMale: Bool) -> Double {
        restingKcalPerDay(weightKg: weightKg, heightCm: heightCm, age: age, isMale: isMale) / 1440
    }

    // MARK: Treadmill (ACSM metabolic equations)

    static let walkMaxMph = 3.7   // top of the range the walking equation is meant for
    static let runMinMph = 5.0    // bottom of the range the running equation is meant for

    /// Gross oxygen cost in ml/kg/min for a treadmill speed and grade.
    /// Walking: 0.1·S + 1.8·S·G + 3.5 — Running: 0.2·S + 0.9·S·G + 3.5 (S in m/min, G as a fraction).
    /// Between the two ranges the result is blended so the estimate doesn't jump.
    static func treadmillVO2(mph: Double, gradePct: Double) -> Double {
        let s = max(0, mph) * 26.8224          // m/min
        let g = max(0, gradePct) / 100
        let walk = 0.1 * s + 1.8 * s * g + 3.5
        let run = 0.2 * s + 0.9 * s * g + 3.5
        if mph <= walkMaxMph { return walk }
        if mph >= runMinMph { return run }
        let f = (mph - walkMaxMph) / (runMinMph - walkMaxMph)
        return walk + (run - walk) * f
    }

    /// Gross kcal/min on a treadmill (1 L of oxygen ≈ 5 kcal).
    static func treadmillKcalPerMin(mph: Double, gradePct: Double, weightKg: Double) -> Double {
        treadmillVO2(mph: mph, gradePct: gradePct) * weightKg / 200
    }

    // MARK: Body-weight trend

    static let kcalPerLb = 3500.0       // rule-of-thumb energy content of a pound of body mass
    static let sedentaryFactor = 1.2    // resting → non-exercise daily expenditure

    struct Trend {
        var entries: Int
        var spanDays: Double
        var lbsPerWeek: Double          // negative = losing
        /// Average daily energy balance implied by the trend; positive = deficit.
        var deficitPerDay: Double { -lbsPerWeek / 7 * Energy.kcalPerLb }
        var preliminary: Bool { spanDays < 21 }
    }

    /// Least-squares slope through the weigh-ins of the last `windowDays`. Needs at least
    /// 4 weigh-ins across 14+ days — anything shorter is mostly water-weight noise.
    static func trend(_ all: [WeightEntry], windowDays: Double = 42, now: Date = Date()) -> Trend? {
        let cutoff = now.addingTimeInterval(-windowDays * 86400)
        let pts = all.filter { $0.date >= cutoff }.sorted { $0.date < $1.date }
        guard pts.count >= 4, let first = pts.first, let last = pts.last else { return nil }
        let span = last.date.timeIntervalSince(first.date) / 86400
        guard span >= 14 else { return nil }
        let xs = pts.map { $0.date.timeIntervalSince(first.date) / 86400 }
        let ys = pts.map { $0.lbs }
        let n = Double(pts.count)
        let mx = xs.reduce(0, +) / n, my = ys.reduce(0, +) / n
        var sxy = 0.0, sxx = 0.0
        for i in pts.indices { sxy += (xs[i] - mx) * (ys[i] - my); sxx += (xs[i] - mx) * (xs[i] - mx) }
        guard sxx > 0 else { return nil }
        return Trend(entries: pts.count, spanDays: span, lbsPerWeek: sxy / sxx * 7)
    }
}

/// One body-weight weigh-in.
struct WeightEntry: Codable, Identifiable {
    var id = UUID()
    var date: Date
    var lbs: Double
}

extension WorkoutRecord {
    /// Active calories for this workout: the stored figure when it was recorded live,
    /// otherwise gross minus an estimated resting share for the workout's duration.
    func activeEstimate(restPerMin: Double) -> Double {
        activeCalories ?? max(0, calories - restPerMin * duration / 60)
    }
}

// MARK: - Live comparison card (Workout tab)

/// Shows the heart-rate estimate next to the treadmill estimate, gross and active,
/// plus how much of the workout actually had heart-rate data behind it.
struct EnergyCompareCard: View {
    @ObservedObject var vm: WorkoutViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Calorie estimates", systemImage: "flame").font(.subheadline.bold())
            HStack {
                Text("").frame(maxWidth: .infinity, alignment: .leading)
                Text("Gross").frame(width: 64, alignment: .trailing)
                Text("Active").frame(width: 64, alignment: .trailing)
            }
            .font(.caption2).foregroundColor(.secondary)
            line("Heart rate", vm.calories, vm.activeCalories)
            if vm.hasTreadmillEstimate {
                line("Speed & grade", vm.treadmillCalories, vm.treadmillActiveCalories)
                Text(comparison).font(.caption).foregroundColor(comparisonColor)
            }
            if vm.duration >= 60, vm.hrCoverage < 0.98 {
                Text("Heart-rate data covers \(Int((vm.hrCoverage * 100).rounded()))% of this workout (\(WorkoutViewModel.clock(vm.hrGapSeconds)) with no reading). The heart-rate estimate only counts time with a reading.")
                    .font(.caption).foregroundColor(.orange)
            }
            Text("Estimates, not measurements. Active = gross minus about \(String(format: "%.1f", vm.restingKcalPerMin)) kcal/min you'd burn at rest."
                 + (vm.hasTreadmillEstimate ? " Speed & grade assumes you aren't holding the handrails." : ""))
                .font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
    }

    private func line(_ label: String, _ gross: Double, _ active: Double) -> some View {
        HStack {
            Text(label).font(.callout).frame(maxWidth: .infinity, alignment: .leading)
            Text("~\(Int(gross))").frame(width: 64, alignment: .trailing)
            Text("~\(Int(active))").frame(width: 64, alignment: .trailing)
        }
        .font(.callout.bold().monospacedDigit())
    }

    /// Difference between the two gross estimates, relative to their mean.
    private var gap: Double? {
        let mean = (vm.calories + vm.treadmillCalories) / 2
        guard vm.duration >= 120, mean > 5 else { return nil }
        return (vm.calories - vm.treadmillCalories) / mean
    }

    private var comparison: String {
        guard let g = gap else { return "Comparing the two estimates once there's a couple of minutes of data." }
        let pct = Int((abs(g) * 100).rounded())
        if pct <= 15 { return "The two estimates agree within \(pct)%." }
        return g > 0
            ? "Heart-rate estimate is \(pct)% higher than speed & grade. Heat, caffeine, fatigue or a low fitness level raise heart rate without raising work done."
            : "Heart-rate estimate is \(pct)% lower than speed & grade. Check speed and grade match the treadmill, and whether heart-rate readings dropped out."
    }

    private var comparisonColor: Color {
        guard let g = gap else { return .secondary }
        return abs(g) <= 0.15 ? .green : .orange
    }
}

// MARK: - Weight-trend reality check (Progress tab)

/// Logs weigh-ins and checks the app's estimated daily expenditure against what the
/// weight trend over several weeks implies.
struct EnergyCheckCard: View {
    @ObservedObject var store: WorkoutStore

    @AppStorage("age") private var age = 40
    @AppStorage("isMale") private var isMale = true
    @AppStorage("weightLbs") private var weightLbs: Double = 165
    @AppStorage("heightIn") private var heightIn = 68
    @AppStorage("avgIntakeKcal") private var avgIntakeKcal = 0

    @State private var newWeight = ""
    @State private var intakeText = ""
    @State private var showAll = false
    @FocusState private var focused: Bool

    private var restPerDay: Double {
        Energy.restingKcalPerDay(weightKg: weightLbs * 0.453592, heightCm: Double(heightIn) * 2.54,
                                 age: age, isMale: isMale)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Weight trend check").font(.headline)
            Text("Log your weight a few times a week. After 2–3 weeks the trend shows whether the calorie estimates are realistic.")
                .font(.caption).foregroundColor(.secondary)

            HStack {
                TextField("Weight (lbs)", text: $newWeight)
                    .keyboardType(.decimalPad).focused($focused)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
                Button("Log") { logWeight() }
                    .buttonStyle(.borderedProminent).tint(.red)
                    .disabled(Double(newWeight) == nil)
            }
            HStack {
                TextField("Avg calories eaten per day (optional)", text: $intakeText)
                    .keyboardType(.numberPad).focused($focused)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
                Button("Set") { avgIntakeKcal = Int(intakeText) ?? 0; focused = false }
                    .buttonStyle(.bordered)
            }

            verdict

            if !store.weights.isEmpty {
                ForEach(store.weights.prefix(showAll ? 60 : 4)) { w in
                    HStack {
                        Text(w.date, format: .dateTime.month().day().year()).font(.caption)
                        Spacer()
                        Text(String(format: "%.1f lbs", w.lbs)).font(.caption.bold().monospacedDigit())
                        Button { store.deleteWeight(w) } label: {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if store.weights.count > 4 {
                    Button(showAll ? "Show fewer" : "Show all \(store.weights.count) weigh-ins") { showAll.toggle() }
                        .font(.caption)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
        .onAppear { if avgIntakeKcal > 0 { intakeText = "\(avgIntakeKcal)" } }
    }

    private func logWeight() {
        guard let v = Double(newWeight), v > 50, v < 700 else { return }
        store.addWeight(lbs: v)
        weightLbs = v            // keep the calorie formulas on your current weight
        newWeight = ""
        focused = false
    }

    @ViewBuilder private var verdict: some View {
        if let t = Energy.trend(store.weights) {
            let workout = store.avgDailyActiveCalories(overLast: t.spanDays, restPerMin: restPerDay / 1440)
            let estimated = restPerDay * Energy.sedentaryFactor + workout
            VStack(alignment: .leading, spacing: 4) {
                factRow("Trend (\(t.entries) weigh-ins, \(Int(t.spanDays.rounded())) days)",
                        String(format: "%+.2f lbs/wk", t.lbsPerWeek))
                factRow(t.deficitPerDay >= 0 ? "Implied daily deficit" : "Implied daily surplus",
                        "~\(Int(abs(t.deficitPerDay).rounded())) kcal")
                factRow("Estimated daily burn", "~\(Int(estimated.rounded())) kcal")
                Text("Estimated burn = resting \(Int(restPerDay.rounded())) × \(String(format: "%.1f", Energy.sedentaryFactor)) for everyday activity + \(Int(workout.rounded())) kcal/day of workout active calories.")
                    .font(.caption2).foregroundColor(.secondary)
                if avgIntakeKcal > 0 {
                    let implied = Double(avgIntakeKcal) + t.deficitPerDay
                    let diff = estimated - implied
                    factRow("Burn implied by intake + trend", "~\(Int(implied.rounded())) kcal")
                    Text(verdictText(diff: diff, implied: implied))
                        .font(.caption.bold())
                        .foregroundColor(abs(diff) <= 0.1 * implied ? .green : .orange)
                } else {
                    Text("If that estimate is right, you're eating about \(Int((estimated - t.deficitPerDay).rounded())) kcal a day. Enter your real average intake above to test it.")
                        .font(.caption.bold())
                }
                if t.preliminary {
                    Text("Preliminary — under 3 weeks of weigh-ins, so water weight can dominate.")
                        .font(.caption2).foregroundColor(.orange)
                }
                Text("Uses ~3,500 kcal per lb, a rough rule; treat differences under about 10% as agreement.")
                    .font(.caption2).foregroundColor(.secondary)
            }
        } else {
            Text(store.weights.isEmpty
                 ? "No weigh-ins yet."
                 : "Need at least 4 weigh-ins spread over 14+ days (within the last 6 weeks) to read a trend.")
                .font(.caption).foregroundColor(.secondary)
        }
    }

    private func verdictText(diff: Double, implied: Double) -> String {
        let n = Int(abs(diff).rounded())
        if abs(diff) <= 0.1 * implied {
            return "Consistent — the estimates and your weight trend agree within \(n) kcal/day."
        }
        return diff > 0
            ? "The estimates look about \(n) kcal/day too high for your trend — or more is being eaten than logged."
            : "The estimates look about \(n) kcal/day too low for your trend — or less is being eaten than logged."
    }

    private func factRow(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(.caption).foregroundColor(.secondary)
            Spacer()
            Text(v).font(.callout.bold().monospacedDigit())
        }
    }
}
