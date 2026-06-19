import SwiftUI

struct FitbitView: View {
    @ObservedObject var fitbit: FitbitService

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    Text("Fitbit").font(.largeTitle.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if fitbit.connected {
                        connectedView
                    } else {
                        setupView
                    }

                    if !fitbit.status.isEmpty {
                        Text(fitbit.status).font(.caption).foregroundColor(.secondary)
                    }
                }
                .padding(20)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var setupView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Pull your daily steps, calories, resting heart rate, and sleep from Fitbit after each workout.")
                .font(.subheadline).foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Fitbit Client ID").font(.caption).foregroundColor(.secondary)
                TextField("Paste your Client ID", text: $fitbit.clientID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
            }

            Button { fitbit.connect() } label: {
                Label("Connect Fitbit", systemImage: "link").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(.green)
            .disabled(fitbit.clientID.trimmingCharacters(in: .whitespaces).isEmpty)

            VStack(alignment: .leading, spacing: 4) {
                Text("First time? Set up a free Fitbit app:").font(.caption.bold())
                Text("1. dev.fitbit.com → Register an App").font(.caption2).foregroundColor(.secondary)
                Text("2. OAuth type: Personal").font(.caption2).foregroundColor(.secondary)
                Text("3. Callback URL: zonealert://fitbit").font(.caption2).foregroundColor(.secondary)
                Text("4. Scopes: activity, heartrate, sleep, profile, weight").font(.caption2).foregroundColor(.secondary)
                Text("5. Copy the Client ID and paste it above.").font(.caption2).foregroundColor(.secondary)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))

            Text("Connecting Fitbit sends your data request to Fitbit's servers (the only part of Zone Alert that uses the internet). Your Fitbit login is handled by Apple's secure web sheet.")
                .font(.caption2).foregroundColor(.secondary)
        }
    }

    private var connectedView: some View {
        VStack(spacing: 16) {
            HStack {
                Label(fitbit.daily.name.isEmpty ? "Connected" : fitbit.daily.name, systemImage: "checkmark.seal.fill")
                    .foregroundColor(.green).font(.subheadline.bold())
                Spacer()
                if fitbit.loading { ProgressView() }
            }

            let d = fitbit.daily
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                stat("Steps", "\(d.steps)", "figure.walk")
                stat("Calories", "\(d.caloriesOut)", "flame.fill")
                stat("Distance", String(format: "%.2f mi", d.distanceMiles), "ruler")
                stat("Active min", "\(d.activeMinutes)", "bolt.fill")
                stat("Resting HR", d.restingHR > 0 ? "\(d.restingHR) bpm" : "—", "heart.fill")
                stat("Sleep", d.sleepMinutes > 0 ? "\(d.sleepMinutes / 60)h \(d.sleepMinutes % 60)m" : "—", "bed.double.fill")
            }
            if !d.date.isEmpty {
                Text("As of \(d.date)").font(.caption2).foregroundColor(.secondary)
            }

            Button { fitbit.sync() } label: {
                Label("Sync now", systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent).tint(.green)

            Button(role: .destructive) { fitbit.disconnect() } label: {
                Label("Disconnect Fitbit", systemImage: "xmark.circle").frame(maxWidth: .infinity)
            }.buttonStyle(.bordered)

            Text("Auto-syncs after each workout you finish.")
                .font(.caption2).foregroundColor(.secondary)
        }
    }

    private func stat(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(spacing: 4) {
            Label(title, systemImage: icon).font(.caption).foregroundColor(.secondary)
            Text(value).font(.title3.bold()).monospacedDigit()
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
    }
}
