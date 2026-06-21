import SwiftUI

/// Weight tracker: log your weight over time, enter what you ate and what you burned,
/// and see your daily deficit + projected weekly loss (1 lb ≈ 3,500 kcal). On-device.
struct WeightView: View {
    @ObservedObject var store: WeightStore
    @ObservedObject var workouts: WorkoutStore
    @Binding var weightLbs: Double
    @AppStorage("maintenanceCal") private var maintenance: Int = 0
    @AppStorage("goalWeightLb") private var goalWeight: Int = 0

    private var key: String { store.todayKey }
    private var today: DayDeficit { store.day(key) }
    private var todayWorkoutKcal: Int { Int(workouts.totals(on: Date()).calories) }
    private var deficit: Int { maintenance + today.burned - today.eaten }
    private var weeklyLb: Double { Double(deficit) * 7.0 / WeightStore.kcalPerPound }

    private var eaten: Binding<Int> { Binding(get: { today.eaten }, set: { store.setEaten($0, for: key) }) }
    private var burned: Binding<Int> { Binding(get: { today.burned }, set: { store.setBurned($0, for: key) }) }
    private var weightInt: Binding<Int> {
        Binding(get: { Int(weightLbs.rounded()) }, set: { weightLbs = Double($0) })
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    Text("Weight").font(.largeTitle.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ledgerCard
                    resultCard
                    weightCard

                    Text("Projection uses 1 lb of fat ≈ 3,500 kcal. Maintenance = what you burn on a rest day (≈ bodyweight × 14 for lightly active); your workout burn stacks on top. Estimates only.")
                        .font(.caption2).foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(18)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { if maintenance == 0 { maintenance = max(1000, Int(weightLbs * 14)) } }
    }

    // MARK: - Cards

    private var ledgerCard: some View {
        card {
            Text("Today").font(.headline)
            row("Calories eaten", value: eaten, unit: "kcal")
            VStack(spacing: 4) {
                row("Workout burned", value: burned, unit: "kcal")
                if todayWorkoutKcal > 0 && todayWorkoutKcal != today.burned {
                    Button { store.setBurned(todayWorkoutKcal, for: key) } label: {
                        Text("Use today's workouts (\(todayWorkoutKcal) kcal)").font(.caption)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            row("Maintenance (rest day)", value: $maintenance, unit: "kcal")
        }
    }

    private var resultCard: some View {
        let losing = deficit > 0
        return card {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Today's deficit").font(.caption).foregroundColor(.secondary)
                    Text("\(deficit > 0 ? "+" : "")\(deficit) kcal")
                        .font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
                        .foregroundColor(losing ? .green : .orange)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(losing ? "Projected loss" : "Projected gain").font(.caption).foregroundColor(.secondary)
                    Text(String(format: "%.2f lb/wk", abs(weeklyLb)))
                        .font(.system(size: 26, weight: .bold, design: .rounded)).monospacedDigit()
                        .foregroundColor(losing ? .green : .orange)
                }
            }
            let week = store.weeklyDeficit(maintenance: maintenance)
            if week.loggedDays > 0 {
                Text("Last 7 days: \(week.kcal) kcal net over \(week.loggedDays) logged day\(week.loggedDays == 1 ? "" : "s") ≈ \(String(format: "%.2f", Double(week.kcal)/WeightStore.kcalPerPound)) lb.")
                    .font(.caption2).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var weightCard: some View {
        card {
            Text("Body weight").font(.headline)
            row("Current weight", value: weightInt, unit: "lb")
            Button { store.logWeight(weightLbs) } label: {
                Label("Log today's weight", systemImage: "scalemass.fill").frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent).tint(.red)

            row("Goal weight", value: $goalWeight, unit: "lb")
            if goalWeight > 0 {
                let toGo = weightLbs - Double(goalWeight)
                Text(toGo > 0
                     ? "\(String(format: "%.1f", toGo)) lb to go" + (weeklyLb > 0 ? " · ~\(Int((toGo / weeklyLb).rounded())) weeks at this rate" : "")
                     : "🎉 At or below your goal.")
                    .font(.caption).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if store.weights.count > 1 { trend }
        }
    }

    private var trend: some View {
        let pts = store.recentWeights(30)
        let vals = pts.map { $0.lb }
        let lo = vals.min() ?? 0, hi = vals.max() ?? 1
        let range = max(hi - lo, 1)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Trend").font(.caption).foregroundColor(.secondary)
                Spacer()
                if let first = vals.first, let last = vals.last {
                    let d = last - first
                    Text("\(d <= 0 ? "▼" : "▲") \(String(format: "%.1f", abs(d))) lb over \(vals.count)")
                        .font(.caption2).foregroundColor(d <= 0 ? .green : .orange)
                }
            }
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                Path { p in
                    for (i, v) in vals.enumerated() {
                        let x = vals.count > 1 ? w * CGFloat(i) / CGFloat(vals.count - 1) : w / 2
                        let y = h - CGFloat((v - lo) / range) * h
                        if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(Color.red, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
            }
            .frame(height: 70)
        }
    }

    // MARK: - Helpers

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
    }

    private func row(_ label: String, value: Binding<Int>, unit: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            NumberField(value: value).frame(width: 78)
            Text(unit).foregroundColor(.secondary)
        }
    }
}
