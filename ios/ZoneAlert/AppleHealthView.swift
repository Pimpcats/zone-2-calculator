import SwiftUI

/// All-day data from **Apple Health** — steps, active calories, resting HR, sleep —
/// kept separate from the H9 workout data. Whatever you wear writes into Apple Health
/// and we read it locally: no internet, no OAuth, no expiring tokens.
struct AppleHealthView: View {
    @ObservedObject var service: AppleHealthService

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    HStack {
                        Text("Health").font(.largeTitle.bold())
                        Spacer()
                        if service.loading { ProgressView() }
                    }

                    if service.authorized {
                        connectedView
                    } else {
                        setupView
                    }

                    if !service.status.isEmpty {
                        Text(service.status).font(.caption).foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(20)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { if service.authorized { service.refresh() } }
    }

    private var setupView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Pull your daily steps, resting heart rate, and sleep from Apple Health — kept completely separate from your H9 workout data.")
                .font(.subheadline).foregroundColor(.secondary)

            Button { service.connect() } label: {
                Label("Connect Apple Health", systemImage: "heart.text.square.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(.pink)

            VStack(alignment: .leading, spacing: 6) {
                Text("Where does this data come from?").font(.caption.bold())
                Text("• Apple Watch / iPhone — automatically").font(.caption2).foregroundColor(.secondary)
                Text("• Fitbit — install a bridge app (Health Sync) to mirror Fitbit → Apple Health").font(.caption2).foregroundColor(.secondary)
                Text("• Garmin / Oura / others — enable their “write to Apple Health” option").font(.caption2).foregroundColor(.secondary)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))

            Text("This stays on your phone — no internet, no account, no login. Reading Health data needs a signed build (AltStore / TestFlight); on a plain sideloaded build it asks but may show no data.")
                .font(.caption2).foregroundColor(.secondary)
        }
    }

    private var connectedView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Connected to Apple Health", systemImage: "checkmark.seal.fill")
                    .foregroundColor(.green).font(.subheadline.bold())
                Spacer()
            }

            let d = service.today
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                stat("Steps", "\(d.steps)", "figure.walk")
                stat("Active", "\(d.activeCalories)", "flame.fill", unit: "kcal")
                stat("Resting HR", d.restingHR > 0 ? "\(d.restingHR)" : "—", "heart.fill", unit: "bpm")
                stat("Sleep", d.sleepMinutes > 0 ? "\(d.sleepMinutes / 60)h \(d.sleepMinutes % 60)m" : "—", "bed.double.fill")
            }

            Button { service.refresh() } label: {
                Label("Refresh", systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent).tint(.pink)

            if service.recent.count > 1 {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Last 7 days").font(.headline)
                    ForEach(service.recent.dropFirst(), id: \.date) { h in
                        HStack {
                            Text(h.date.formatted(.dateTime.weekday(.abbreviated).month().day()))
                                .font(.caption.monospacedDigit())
                            Spacer()
                            Text("\(h.steps) steps" +
                                 (h.restingHR > 0 ? " · \(h.restingHR) bpm" : "") +
                                 (h.sleepMinutes > 0 ? " · \(h.sleepMinutes / 60)h\(h.sleepMinutes % 60)m" : ""))
                                .font(.caption).foregroundColor(.secondary)
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04)))
                    }
                }
            }

            Text("Reads steps, active calories, resting heart rate, and sleep for the last 7 days. Pull to refresh anytime.")
                .font(.caption2).foregroundColor(.secondary)
        }
    }

    private func stat(_ title: String, _ value: String, _ icon: String, unit: String = "") -> some View {
        VStack(spacing: 4) {
            Label(title, systemImage: icon).font(.caption).foregroundColor(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.title3.bold()).monospacedDigit()
                if !unit.isEmpty { Text(unit).font(.caption2).foregroundColor(.secondary) }
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
    }
}
