import Foundation
import SwiftUI

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
            if vm.duration >= 60 {
                let c = vm.hrCoverage
                Text("Heart-rate data: \(pct(c.measured)) measured · \(pct(c.interpolated)) interpolated · \(pct(c.missing)) missing")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(c.missing > 0.02 || c.interpolated > 0.05 ? .orange : .secondary)
                if c.missing > 0.02 {
                    Text("\(WorkoutViewModel.clock(vm.hrMissingSeconds)) had no heart-rate reading and adds nothing to the heart-rate estimate, so that figure is low for this workout.")
                        .font(.caption2).foregroundColor(.orange)
                }
            }
            Text("Estimates from general formulas, not measurements — the two are calculated separately and never blended. Active = gross minus about \(String(format: "%.1f", vm.restingKcalPerMin)) kcal/min you'd burn at rest."
                 + (vm.hasTreadmillEstimate ? " Speed & grade assumes you aren't holding the handrails." : ""))
                .font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
    }

    private func pct(_ share: Double) -> String { "\(Int((share * 100).rounded()))%" }

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
    @AppStorage("avgIntakeKcal") private var avgIntakeKcal = 0   // 0 = not entered (unknown)

    @State private var newWeight = ""
    @State private var intakeText = ""
    @State private var showAll = false
    @State private var intakeNote = ""
    @FocusState private var focused: Bool

    private var restPerDay: Double {
        Energy.restingKcalPerDay(weightKg: weightLbs * Energy.kgPerLb, heightCm: Double(heightIn) * Energy.cmPerInch,
                                 age: age, isMale: isMale)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Weight trend check").font(.headline)
            Text("Log your weight a few times a week. After 3 weeks (4 or more is better) the trend shows whether the calorie estimates are realistic.")
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
                Button("Set") { setIntake() }
                    .buttonStyle(.bordered)
            }
            if !intakeNote.isEmpty {
                Text(intakeNote).font(.caption2).foregroundColor(.orange)
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

    /// Blank clears the intake (back to "unknown"); an implausible number is rejected
    /// rather than stored, so it can never be read as a real intake.
    private func setIntake() {
        focused = false
        let trimmed = intakeText.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            avgIntakeKcal = 0
            intakeNote = ""
        } else if let v = Int(trimmed), Energy.validIntake(v) != nil {
            avgIntakeKcal = v
            intakeNote = ""
        } else {
            intakeNote = "Enter a daily average between 500 and 10,000 kcal, or leave it blank."
        }
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
            let workout = store.avgDailyActiveCalories(from: t.start, to: t.end, restPerMin: restPerDay / 1440)
            let estimated = restPerDay * Energy.sedentaryFactor + workout
            VStack(alignment: .leading, spacing: 4) {
                factRow("\(t.preliminary ? "Preliminary trend" : "Trend") (\(t.entries) weigh-ins, \(Int(t.spanDays.rounded())) days)",
                        String(format: "%+.2f lbs/wk", t.lbsPerWeek))
                if t.preliminary {
                    Text("Preliminary — under 3 weeks between your first and last weigh-in, so water weight can swamp the real change. No comparison is made until there are 3 weeks of data.")
                        .font(.caption).foregroundColor(.orange)
                } else {
                    factRow(t.deficitPerDay >= 0 ? "Implied daily deficit" : "Implied daily surplus",
                            "~\(Int(abs(t.deficitPerDay).rounded())) kcal")
                    factRow("Estimated daily burn", "~\(Int(estimated.rounded())) kcal")
                    Text("Estimated burn = resting \(Int(restPerDay.rounded())) × \(String(format: "%.1f", Energy.sedentaryFactor)) for everyday activity + \(Int(workout.rounded())) kcal/day of workout active calories.")
                        .font(.caption2).foregroundColor(.secondary)
                    if let implied = Energy.impliedBurn(intakeKcalPerDay: avgIntakeKcal, trend: t) {
                        factRow("Burn implied by intake + trend", "~\(Int(implied.rounded())) kcal")
                        let result = Energy.compare(estimated: estimated, implied: implied)
                        Text(verdictText(result, diff: estimated - implied))
                            .font(.caption.bold())
                            .foregroundColor(result == .consistent ? .green : .orange)
                    } else {
                        Text("Calorie intake not entered, so it is treated as unknown (not zero) and no comparison is made. If the estimate above is right, you're eating about \(Int((estimated - t.deficitPerDay).rounded())) kcal a day — enter your real average to test it.")
                            .font(.caption.bold())
                    }
                    if !t.preferredLength {
                        Text("3 weeks of data — usable, but 4 or more weeks gives a steadier trend.")
                            .font(.caption2).foregroundColor(.orange)
                    }
                    Text("Uses ~3,500 kcal per lb and one average intake figure, both rough; differences under about 10% count as agreement.")
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
        } else {
            Text(store.weights.isEmpty
                 ? "No weigh-ins yet."
                 : "Not enough weigh-ins to read a trend: needs at least 4, spread over 14+ days, within the last 8 weeks.")
                .font(.caption).foregroundColor(.secondary)
        }
    }

    private func verdictText(_ result: Energy.Agreement, diff: Double) -> String {
        let n = Int(abs(diff).rounded())
        switch result {
        case .consistent:
            return "Consistent — the estimates and your weight trend agree within \(n) kcal/day."
        case .estimateHigh:
            return "The estimates look about \(n) kcal/day too high for your trend — or more is being eaten than entered."
        case .estimateLow:
            return "The estimates look about \(n) kcal/day too low for your trend — or less is being eaten than entered."
        }
    }

    private func factRow(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(.caption).foregroundColor(.secondary)
            Spacer()
            Text(v).font(.callout.bold().monospacedDigit())
        }
    }
}
