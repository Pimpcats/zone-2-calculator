import SwiftUI

/// A month calendar to browse recorded days/weeks/months (no future navigation).
/// Days with activity show a dot; tap any day to see that day's detail.
struct CalendarView: View {
    @ObservedObject var store: WorkoutStore

    private let cal = Calendar.current
    private let cols = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private let weekdaySymbols = ["S", "M", "T", "W", "T", "F", "S"]

    @State private var month: Date = Calendar.current.date(
        from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
    @State private var selected: Date? = Calendar.current.startOfDay(for: Date())

    private var today: Date { cal.startOfDay(for: Date()) }
    private var currentMonth: Date {
        cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
    }
    private var canGoForward: Bool { month < currentMonth }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            HStack(spacing: 4) {
                ForEach(weekdaySymbols.indices, id: \.self) { i in
                    Text(weekdaySymbols[i]).font(.caption2.bold()).foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: cols, spacing: 4) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, day in cell(day) }
            }
            if let s = selected { detail(for: s) }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
    }

    private var header: some View {
        HStack {
            Text(month.formatted(.dateTime.month(.wide).year())).font(.headline)
            Spacer()
            Button { shift(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(.bordered)
            Button { shift(1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.bordered).disabled(!canGoForward)
        }
    }

    private func shift(_ n: Int) {
        if let m = cal.date(byAdding: .month, value: n, to: month), m <= currentMonth {
            month = m
        }
    }

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
    private func cell(_ day: Date?) -> some View {
        if let day = day {
            let future = day > today
            let has = store.hasData(on: day)
            let isSel = selected.map { cal.isDate($0, inSameDayAs: day) } ?? false
            Button { if !future { selected = day } } label: {
                VStack(spacing: 2) {
                    Text("\(cal.component(.day, from: day))")
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

    @ViewBuilder
    private func detail(for day: Date) -> some View {
        let recs = store.records(on: day)
        let meas = store.measurements(on: day)
        VStack(alignment: .leading, spacing: 6) {
            Divider().overlay(Color.white.opacity(0.1))
            Text(day.formatted(.dateTime.weekday(.wide).month().day())).font(.subheadline.bold())
            if recs.isEmpty && meas.isEmpty {
                Text("No activity recorded.").font(.caption).foregroundColor(.secondary)
            } else {
                let t = store.totals(on: day)
                if t.count > 0 {
                    Text("\(t.count) workout\(t.count == 1 ? "" : "s") · \(WorkoutViewModel.clock(t.duration)) · \(String(format: "%.2f mi", t.miles)) · \(Int(t.calories)) kcal")
                        .font(.caption).foregroundColor(.secondary)
                }
                ForEach(recs) { r in
                    HStack {
                        Text(r.date.formatted(date: .omitted, time: .shortened))
                        Spacer()
                        Text("\(WorkoutViewModel.clock(r.duration)) · avg \(r.avgBpm) bpm")
                    }.font(.caption)
                }
                ForEach(meas) { m in
                    HStack {
                        Text(m.kind == "resting" ? "Resting HR test" : "Threshold test")
                        Spacer()
                        Text("\(m.bpm) bpm")
                    }.font(.caption).foregroundColor(.secondary)
                }
            }
        }
    }
}
