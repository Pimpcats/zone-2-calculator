import SwiftUI

/// Simple weekly weight-loss calculator: enter today's total calories burned and eaten,
/// see your deficit and how much you'd lose per week (1 lb ≈ 3,500 kcal). On-device.
struct WeightView: View {
    @ObservedObject var store: WeightStore
    @ObservedObject var workouts: WorkoutStore

    private var key: String { store.todayKey }
    private var today: DayDeficit { store.day(key) }
    private var deficit: Int { today.burned - today.eaten }       // + = losing, − = gaining
    private var weeklyLb: Double { Double(deficit) * 7.0 / WeightStore.kcalPerPound }
    private var workoutKcal: Int { Int(workouts.totals(on: Date()).calories) }
    private var losing: Bool { deficit >= 0 }

    private var burned: Binding<Int> { Binding(get: { today.burned }, set: { store.setBurned($0, for: key) }) }
    private var eaten: Binding<Int> { Binding(get: { today.eaten }, set: { store.setEaten($0, for: key) }) }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    Text("Weight loss").font(.largeTitle.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)

                    card {
                        Text("Today").font(.headline)
                        row("Calories burned (total)", value: burned, unit: "kcal")
                        row("Calories eaten", value: eaten, unit: "kcal")
                        if workoutKcal > 0 {
                            Text("Zone Alert logged \(workoutKcal) kcal from today's workouts — make sure that's included in your total burned.")
                                .font(.caption2).foregroundColor(.secondary)
                        }
                    }

                    card {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(losing ? "Daily deficit" : "Daily surplus").font(.caption).foregroundColor(.secondary)
                                Text("\(abs(deficit)) kcal")
                                    .font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
                                    .foregroundColor(losing ? .green : .orange)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(losing ? "Lose / week" : "Gain / week").font(.caption).foregroundColor(.secondary)
                                Text(String(format: "%.2f lb", abs(weeklyLb)))
                                    .font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
                                    .foregroundColor(losing ? .green : .orange)
                            }
                        }
                    }

                    Text("Deficit = calories burned − calories eaten. “Burned (total)” means your whole day's calories out — resting + daily activity + workouts — i.e. the number your watch or Fitbit shows for the day. 1 lb of fat ≈ 3,500 kcal, so a 500/day deficit ≈ 1 lb/week. Estimate only.")
                        .font(.caption2).foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(18)
            }
        }
        .preferredColorScheme(.dark)
    }

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
            NumberField(value: value).frame(width: 84)
            Text(unit).foregroundColor(.secondary)
        }
    }
}
