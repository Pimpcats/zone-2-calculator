import SwiftUI

/// A merged calendar + day review. A month calendar sits at the top (shown by default,
/// collapsible under the selected date); tap any day to see that day's workout review —
/// distance, calories, pace, HR, duration, and time-in-zone.
struct DayReviewView: View {
    @ObservedObject var store: WorkoutStore
    @State private var day = Calendar.current.startOfDay(for: Date())
    @State private var month: Date = Calendar.current.date(
        from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
    @State private var showCalendar = true

    private let cal = Calendar.current
    private let cols = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private let weekdaySymbols = ["S", "M", "T", "W", "T", "F", "S"]

    private var today: Date { cal.startOfDay(for: Date()) }
    private var isToday: Bool { cal.isDateInToday(day) }
    private var currentMonth: Date {
        cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
    }
    private var canGoForward: Bool { month < currentMonth }

    var body: some View {
        let t = store.totals(on: day)
        let tiz = store.timeInZoneTotals(on: day)
        let hr = store.hrSummary(on: day)
        let pace = t.miles > 0.02 ? t.duration / t.miles : nil

        VStack(spacing: 12) {
            // Selected-date header — tap to collapse/expand the calendar
            HStack {
                Button { shiftDay(-1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.bordered)
                Spacer()
                Button { withAnimation { showCalendar.toggle() } } label: {
                    VStack(spacing: 1) {
                        HStack(spacing: 4) {
                            Text(isToday ? "Today" : day.formatted(.dateTime.weekday(.wide))).font(.headline)
                            Image(systemName: showCalendar ? "chevron.up" : "chevron.down").font(.caption2)
                        }
                        Text(day.formatted(.dateTime.month().day().year()))
                            .font(.caption).foregroundColor(.secondary)
                    }
                    .foregroundColor(.primary)
                }
                .buttonStyle(.plain)
                Spacer()
                Button { shiftDay(1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.bordered).disabled(isToday)
            }

            // Month calendar (shown by default, collapsible)
            if showCalendar {
                VStack(spacing: 10) {
                    HStack {
                        Text(month.formatted(.dateTime.month(.wide).year())).font(.subheadline.bold())
                        Spacer()
                        Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                            .buttonStyle(.bordered)
                        Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                            .buttonStyle(.bordered).disabled(!canGoForward)
                    }
                    HStack(spacing: 4) {
                        ForEach(weekdaySymbols.indices, id: \.self) { i in
                            Text(weekdaySymbols[i]).font(.caption2.bold()).foregroundColor(.secondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    LazyVGrid(columns: cols, spacing: 4) {
                        ForEach(Array(cells.enumerated()), id: \.offset) { _, d in cell(d) }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Divider().overlay(Color.white.opacity(0.1))

            // Selected day's review
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

    // MARK: - Navigation

    private func shiftDay(_ n: Int) {
        if let d = cal.date(byAdding: .day, value: n, to: day), d <= today {
            day = d
            month = cal.date(from: cal.dateComponents([.year, .month], from: d)) ?? month
        }
    }

    private func shiftMonth(_ n: Int) {
        if let m = cal.date(byAdding: .month, value: n, to: month), m <= currentMonth {
            month = m
        }
    }

    // MARK: - Calendar grid

    private var cells: [Date?] {
        guard let range = cal.range(of: .day, in: .month, for: month),
              let first = cal.date(from: cal.dateComponents([.year, .month], from: month))
        else { return [] }
        let leading = cal.component(.weekday, from: first) - 1
        var out: [Date?] = Array(repeating: nil, count: leading)
        for d in range { out.append(cal.date(byAdding: .day, value: d - 1, to: first)) }
        return out
    }

    @ViewBuilder
    private func cell(_ d: Date?) -> some View {
        if let d = d {
            let future = d > today
            let has = store.hasData(on: d)
            let isSel = cal.isDate(day, inSameDayAs: d)
            Button { if !future { day = d } } label: {
                VStack(spacing: 2) {
                    Text("\(cal.component(.day, from: d))")
                        .font(.callout)
                        .foregroundColor(future ? Color.gray.opacity(0.4) : (isSel ? .black : .white))
                    Circle().fill(has ? (isSel ? Color.black : Color.red) : .clear)
                        .frame(width: 5, height: 5)
                }
                .frame(maxWidth: .infinity).frame(height: 36)
                .background(isSel ? Color.red : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .disabled(future)
        } else {
            Color.clear.frame(height: 36)
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
