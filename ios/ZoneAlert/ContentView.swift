import SwiftUI

struct ContentView: View {
    @StateObject private var hr = HeartRateManager()
    @AppStorage("age") private var age: Int = 40
    @AppStorage("targetZone") private var targetZone: Int = 2

    private var mhr: Int { Zones.mhr(age: age) }
    private var zoneNumber: Int { hr.currentZone ?? -1 }
    private var zoneColor: Color {
        guard let z = hr.currentZone else { return Color(white: 0.4) }
        return Zones.meta(z).color
    }
    private var belowTarget: Bool {
        guard let z = hr.currentZone, hr.connected else { return false }
        return z < targetZone
    }

    var body: some View {
        ZStack {
            (belowTarget ? Color.red.opacity(0.18) : Color(red: 0.06, green: 0.08, blue: 0.10))
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.3), value: belowTarget)

            ScrollView {
                VStack(spacing: 22) {
                    header
                    liveCard
                    settingsCard
                    controls
                    Text(hr.statusText)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    disclaimer
                }
                .padding(20)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            hr.age = age
            hr.targetZone = targetZone
            requestNotifications()
        }
        .onChange(of: age) { hr.age = $0 }
        .onChange(of: targetZone) { hr.targetZone = $0 }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 4) {
            Text("Zone Alert").font(.largeTitle.bold())
            Text("Background heart-rate zone alerts")
                .font(.subheadline).foregroundColor(.secondary)
        }
        .padding(.top, 8)
    }

    private var liveCard: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: hr.connected ? "heart.fill" : "heart")
                    .foregroundColor(zoneColor)
                    .font(.system(size: 34))
                    .symbolEffect(.pulse, isActive: hr.connected)
                Text(hr.bpm.map(String.init) ?? "--")
                    .font(.system(size: 80, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            Text("BPM").font(.caption).tracking(2).foregroundColor(.secondary)

            Text(zoneLabel)
                .font(.headline.bold())
                .padding(.horizontal, 18).padding(.vertical, 8)
                .background(Capsule().fill(zoneColor))
                .foregroundColor(.black)

            Text("Target: Zone \(targetZone)  (≥ \(Zones.lowerBpm(zone: targetZone, mhr: mhr)) bpm)")
                .font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(zoneColor.opacity(0.6), lineWidth: 1))
    }

    private var zoneLabel: String {
        guard hr.connected, let z = hr.currentZone else { return "Not connected" }
        return z == 0 ? "Below Zone 1" : "Zone \(z) · \(Zones.meta(z).name)"
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Age").foregroundColor(.secondary)
                Spacer()
                Stepper("\(age)", value: $age, in: 10...100).fixedSize()
            }
            Divider().overlay(Color.white.opacity(0.1))
            VStack(alignment: .leading, spacing: 8) {
                Text("Target zone — alert me if I drop below it").foregroundColor(.secondary).font(.subheadline)
                Picker("Target zone", selection: $targetZone) {
                    ForEach(Zones.all) { z in
                        Text("Zone \(z.id) · \(z.name)").tag(z.id)
                    }
                }
                .pickerStyle(.segmented)
            }
            Text("Max HR ≈ 220 − \(age) = \(mhr) bpm")
                .font(.caption).foregroundColor(.secondary)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.05)))
    }

    private var controls: some View {
        VStack(spacing: 10) {
            if hr.connected {
                Button(role: .destructive) { hr.disconnect() } label: {
                    Label("Disconnect", systemImage: "xmark.circle").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(.gray)
            } else {
                Button { hr.startScanning() } label: {
                    Label("Connect strap", systemImage: "antenna.radiowaves.left.and.right").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(.red)
                .disabled(!hr.bluetoothReady)
            }
            Button { hr.sendTestAlert() } label: {
                Label("Test alert", systemImage: "bell.badge").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private var disclaimer: some View {
        Text("Keeps alerting in the background while your strap stays connected. A training aid, not a medical device.")
            .font(.caption2).foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .padding(.top, 4)
    }

    private func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }
}

#Preview {
    ContentView()
}
