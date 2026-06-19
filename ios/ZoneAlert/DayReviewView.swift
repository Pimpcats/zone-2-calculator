import SwiftUI

/// A "day at a glance" browser — flip through past days with ‹ › to see each day's
/// distance, calories, pace, HR, duration, and time-in-zone (like the live screen).
struct DayReviewView: View {
    @ObservedObject var store: WorkoutStore
    @State private var day = Calendar.current.startOfDay(for: Date())
    @State private var showPicker = false
    private let cal = Calendar.current
    private var isToday: Bool { cal.isDateInToday(day) }

    var body: some View {
        let t = store.totals(on: day)
        let tiz = store.timeInZoneTotals(on: day)
        let hr = store.hrSummary(on: day)
        let pace = t.miles > 0.02 ? t.duration / t.miles : nil

        VStack(spacing: 12) {
            // Day navigation — tap the date to pop a calendar
            HStack {
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.bordered)
                Spacer()
                Button { withAnimation { showPicker.toggle() } } label: {
                    VStack(spacing: 1) {
                        HStack(spacing: 4) {
                            Text(isToday ? "Today" : day.formatted(.dateTime.weekday(.wide))).font(.headline)
                            Image(systemName: "calendar").font(.caption2)
                        }
                        Text(day.formatted(.dateTime.month().day().year()))
                            .font(.caption).foregroundColor(.secondary)
                    }
                    .foregroundColor(.primary)
                }
                .buttonStyle(.plain)
                Spacer()
                Button { shift(1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.bordered).disabled(isToday)
            }

            if showPicker {
                DatePicker("", selection: $day, in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .onChange(of: day) { _ in withAnimation { showPicker = false } }
            }

            if t.count == 0 {
                Text("No workouts this day.")
                    .font(.caption).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
            } else {
                HStack(spacing: 12) {
                    metric("Distance", String(format: "%.2f", t.miles), "mi", .red)
                    metric("Calories", "\(Int(t.calories))", "kcal", .red)
                }
                HStack(spacing: 12) {
                    metric("Pace", WorkoutViewModel.pace(pace), "min/mi", .red)
                    metric("Avg HR", hr.avg > 0 ? "\(hr.avg)" : "--", "bpm", Color(red: 0.30, green: 0.66, blue: 1.0))
                }
                metric("Duration", WorkoutViewModel.clock(t.duration), "", .red)

                Text("Time in zone").font(.caption).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                TimeInZoneView(timeInZone: tiz, currentZone: -1)

                Text("\(t.count) workout\(t.count == 1 ? "" : "s") · peak \(hr.peak) bpm")
                    .font(.caption2).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
    }

    private func shift(_ n: Int) {
        if let d = cal.date(byAdding: .day, value: n, to: day), d <= cal.startOfDay(for: Date()) {
            day = d
        }
    }

    private func metric(_ title: String, _ value: String, _ unit: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundColor(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.system(size: 26, weight: .bold, design: .rounded))
                    .monospacedDigit().foregroundColor(color).lineLimit(1).minimumScaleFactor(0.6)
                Text(unit).font(.caption2).foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
