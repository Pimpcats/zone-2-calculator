import SwiftUI
import UserNotifications

struct ContentView: View {
    @StateObject private var vm = WorkoutViewModel()

    @AppStorage("age") private var age: Int = 40
    @AppStorage("targetZone") private var targetZone: Int = 2
    @AppStorage("weightKg") private var weightKg: Double = 75
    @AppStorage("isMale") private var isMale: Bool = true
    @State private var showSettings = false

    private var belowTarget: Bool {
        vm.connected && vm.currentZone < targetZone && vm.active
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            (belowTarget ? Color.red.opacity(0.16) : Color.clear)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.3), value: belowTarget)

            VStack(spacing: 0) {
                topBar
                ScrollView {
                    VStack(spacing: 18) {
                        metricsGrid
                        pager
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                }
                bottomBar
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { syncSettings(); requestNotifications(); vm.loc.requestAuthorization() }
        .onChange(of: age) { _ in syncSettings() }
        .onChange(of: targetZone) { _ in syncSettings() }
        .onChange(of: weightKg) { _ in syncSettings() }
        .onChange(of: isMale) { _ in syncSettings() }
        .sheet(isPresented: $showSettings) { settingsSheet }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Zone Alert").font(.headline.bold())
                Text(vm.connected ? (vm.statusText) : "Strap not connected")
                    .font(.caption2)
                    .foregroundColor(vm.connected ? .green : .secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill").font(.title3).foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    // MARK: - Metrics

    private var metricsGrid: some View {
        VStack(spacing: 18) {
            HStack(spacing: 14) {
                MetricCell(icon: "ruler", title: "Distance",
                           value: String(format: "%.2f", vm.distanceMiles), unit: "mi")
                MetricCell(icon: "flame.fill", title: "Calories",
                           value: "\(Int(vm.calories))", unit: "kcal")
            }
            HStack(spacing: 14) {
                MetricCell(icon: "speedometer", title: "Pace",
                           value: WorkoutViewModel.pace(vm.paceSecPerMile), unit: "min/mi")
                MetricCell(icon: "heart.fill", title: "Heart rate",
                           value: vm.bpm.map(String.init) ?? "--", unit: "bpm",
                           valueColor: Color(red: 0.30, green: 0.66, blue: 1.0))
            }
            MetricCell(icon: "timer", title: "Duration",
                       value: WorkoutViewModel.clock(vm.duration), unit: "")
        }
    }

    // MARK: - Swipeable graph / time-in-zone

    private var pager: some View {
        TabView {
            VStack(alignment: .leading, spacing: 6) {
                Text("Heart-rate zones (live)").font(.caption).foregroundColor(.secondary)
                ZoneGraphView(history: vm.hrHistory, mhr: vm.mhr, bpm: vm.bpm)
            }
            .padding(.bottom, 28)

            VStack(alignment: .leading, spacing: 6) {
                Text("Time in zone").font(.caption).foregroundColor(.secondary)
                TimeInZoneView(timeInZone: vm.timeInZone, currentZone: vm.currentZone)
                Spacer(minLength: 0)
            }
            .padding(.bottom, 28)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .frame(height: 280)
    }

    // MARK: - Bottom control bar

    private var bottomBar: some View {
        HStack {
            // Left: connect / strap
            controlButton(
                title: vm.connected ? "Connected" : "Connect",
                icon: vm.connected ? "antenna.radiowaves.left.and.right.circle.fill" : "antenna.radiowaves.left.and.right",
                color: vm.connected ? .green : .red
            ) {
                if vm.connected { vm.disconnectStrap() } else { vm.connect() }
            }
            .disabled(!vm.bluetoothReady && !vm.connected)

            Spacer()

            // Center: start / pause
            Button {
                if vm.active { vm.pause() } else { vm.start() }
            } label: {
                ZStack {
                    Circle().fill(Color.red).frame(width: 72, height: 72)
                    Image(systemName: vm.active ? "pause.fill" : "play.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                }
            }

            Spacer()

            // Right: reset
            controlButton(title: "Reset", icon: "arrow.counterclockwise", color: .secondary) {
                vm.reset()
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(Color(white: 0.07).ignoresSafeArea(edges: .bottom))
    }

    private func controlButton(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.title3)
                Text(title).font(.caption2)
            }
            .foregroundColor(color)
            .frame(width: 76)
        }
    }

    // MARK: - Settings sheet

    private var settingsSheet: some View {
        NavigationView {
            Form {
                Section("You") {
                    Stepper("Age: \(age)", value: $age, in: 10...100)
                    Picker("Sex", selection: $isMale) {
                        Text("Male").tag(true)
                        Text("Female").tag(false)
                    }
                    Stepper("Weight: \(Int(weightKg)) kg", value: $weightKg, in: 30...200, step: 1)
                }
                Section("Target zone") {
                    Picker("Alert if below", selection: $targetZone) {
                        ForEach(Zones.all) { z in Text("Zone \(z.id) · \(z.name)").tag(z.id) }
                    }
                }
                Section {
                    Button("Test alert") { vm.hrm.sendTestAlert() }
                } footer: {
                    Text("Max HR ≈ 220 − \(age) = \(vm.mhr) bpm. Distance & pace use GPS; calories are an HR-based estimate.")
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showSettings = false } } }
        }
    }

    // MARK: - Helpers

    private func syncSettings() {
        vm.age = age
        vm.targetZone = targetZone
        vm.weightKg = weightKg
        vm.isMale = isMale
    }

    private func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }
}

#Preview {
    ContentView()
}
