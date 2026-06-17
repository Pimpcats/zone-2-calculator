import SwiftUI
import UserNotifications

// MARK: - Root (tabs + settings source of truth)

struct ContentView: View {
    @StateObject private var vm = WorkoutViewModel()

    @AppStorage("age") private var age: Int = 40
    @AppStorage("isMale") private var isMale: Bool = true
    @AppStorage("weightKg") private var weightKg: Double = 75
    @AppStorage("restingHR") private var restingHR: Int = 60
    @AppStorage("lowZone") private var lowZone: Int = 2
    @AppStorage("highZone") private var highZone: Int = 3
    @AppStorage("useMeasuredMax") private var useMeasuredMax: Bool = false
    @AppStorage("measuredMax") private var measuredMax: Int = 0

    var body: some View {
        TabView {
            WorkoutView(vm: vm)
                .tabItem { Label("Workout", systemImage: "figure.run") }
            VO2MaxView(vm: vm, restingHR: $restingHR,
                       useMeasuredMax: $useMeasuredMax, measuredMax: $measuredMax)
                .tabItem { Label("VO2 Max", systemImage: "lungs.fill") }
            SettingsView(vm: vm, age: $age, isMale: $isMale, weightKg: $weightKg,
                         restingHR: $restingHR, lowZone: $lowZone, highZone: $highZone,
                         useMeasuredMax: $useMeasuredMax, measuredMax: $measuredMax)
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .tint(.red)
        .preferredColorScheme(.dark)
        .onAppear { applySettings(); requestNotifications(); vm.loc.requestAuthorization() }
        .onChange(of: age) { _ in applySettings() }
        .onChange(of: isMale) { _ in applySettings() }
        .onChange(of: weightKg) { _ in applySettings() }
        .onChange(of: restingHR) { _ in applySettings() }
        .onChange(of: lowZone) { _ in applySettings() }
        .onChange(of: highZone) { _ in applySettings() }
        .onChange(of: useMeasuredMax) { _ in applySettings() }
        .onChange(of: measuredMax) { _ in applySettings() }
    }

    private func applySettings() {
        let override = (useMeasuredMax && measuredMax > 0) ? measuredMax : nil
        vm.apply(age: age, isMale: isMale, weightKg: weightKg, restingHR: restingHR,
                 lowZone: lowZone, highZone: highZone, mhrOverride: override)
    }

    private func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }
}

// MARK: - Workout dashboard

struct WorkoutView: View {
    @ObservedObject var vm: WorkoutViewModel

    private var tooLow: Bool { vm.connected && vm.active && (vm.bpm ?? 999) < vm.floorBpm }
    private var tooHigh: Bool { vm.connected && vm.active && (vm.bpm ?? 0) > vm.ceilingBpm }
    private var outOfBand: Bool { tooLow || tooHigh }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            (tooHigh ? Color.red.opacity(0.18) : (tooLow ? Color.blue.opacity(0.16) : Color.clear))
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.3), value: outOfBand)

            VStack(spacing: 0) {
                topBar
                ScrollView {
                    VStack(spacing: 18) {
                        bandBar
                        metricsGrid
                        pager
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 6)
                }
                bottomBar
            }
        }
    }

    private var topBar: some View {
        HStack {
            Image(systemName: "heart.fill").foregroundColor(.red)
            VStack(alignment: .leading, spacing: 2) {
                Text("Workout").font(.headline.bold())
                Text(vm.connected ? vm.statusText : "Strap not connected")
                    .font(.caption2)
                    .foregroundColor(vm.connected ? .green : .secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
    }

    private var bandBar: some View {
        HStack(spacing: 0) {
            bandPill(title: "Don't drop below", value: vm.floorBpm, color: .cyan, active: tooLow)
            Spacer(minLength: 8)
            bandPill(title: "Don't exceed", value: vm.ceilingBpm, color: .orange, active: tooHigh)
        }
    }

    private func bandPill(title: String, value: Int, color: Color, active: Bool) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.caption2).foregroundColor(.secondary)
            Text("\(value) bpm").font(.title3.bold().monospacedDigit()).foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12).fill(color.opacity(active ? 0.35 : 0.10)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(color, lineWidth: active ? 2 : 0))
    }

    private var metricsGrid: some View {
        VStack(spacing: 16) {
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

    private var pager: some View {
        TabView {
            VStack(alignment: .leading, spacing: 6) {
                Text("Heart-rate zones (live)").font(.caption).foregroundColor(.secondary)
                ZoneGraphView(history: vm.hrHistory, mhr: vm.mhr, bpm: vm.bpm)
            }.padding(.bottom, 28)

            VStack(alignment: .leading, spacing: 6) {
                Text("Time in zone").font(.caption).foregroundColor(.secondary)
                TimeInZoneView(timeInZone: vm.timeInZone, currentZone: vm.currentZone)
                Spacer(minLength: 0)
            }.padding(.bottom, 28)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .frame(height: 280)
    }

    private var bottomBar: some View {
        HStack {
            controlButton(title: vm.connected ? "Connected" : "Connect",
                          icon: vm.connected ? "antenna.radiowaves.left.and.right.circle.fill" : "antenna.radiowaves.left.and.right",
                          color: vm.connected ? .green : .red) {
                if vm.connected { vm.disconnectStrap() } else { vm.connect() }
            }
            .disabled(!vm.bluetoothReady && !vm.connected)

            Spacer()

            Button { if vm.active { vm.pause() } else { vm.start() } } label: {
                ZStack {
                    Circle().fill(Color.red).frame(width: 72, height: 72)
                    Image(systemName: vm.active ? "pause.fill" : "play.fill")
                        .font(.system(size: 28, weight: .bold)).foregroundColor(.white)
                }
            }

            Spacer()

            controlButton(title: "Reset", icon: "arrow.counterclockwise", color: .secondary) { vm.reset() }
        }
        .padding(.horizontal, 28).padding(.top, 10).padding(.bottom, 6)
        .background(Color(white: 0.07).ignoresSafeArea(edges: .bottom))
    }

    private func controlButton(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.title3)
                Text(title).font(.caption2)
            }
            .foregroundColor(color).frame(width: 76)
        }
    }
}

// MARK: - VO2 Max / max-HR test

struct VO2MaxView: View {
    @ObservedObject var vm: WorkoutViewModel
    @Binding var restingHR: Int
    @Binding var useMeasuredMax: Bool
    @Binding var measuredMax: Int

    private var hrMax: Int { vm.peakBpm > 0 ? vm.peakBpm : vm.mhr }
    private var vo2: Double { vm.vo2maxEstimate(usingMax: hrMax) }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    Text("VO₂ Max & Max-HR Test")
                        .font(.title2.bold()).frame(maxWidth: .infinity, alignment: .leading)

                    Text("Warm up, then push progressively harder to your honest limit. Your highest heart rate is captured below — lock it in as your Max HR to drive your zone alerts.")
                        .font(.footnote).foregroundColor(.secondary)

                    HStack(spacing: 14) {
                        bigStat(title: "Current", value: vm.bpm.map(String.init) ?? "--",
                                unit: "bpm", color: Color(red: 0.30, green: 0.66, blue: 1.0))
                        bigStat(title: "Peak this test", value: vm.peakBpm > 0 ? "\(vm.peakBpm)" : "--",
                                unit: "bpm", color: .red)
                    }

                    VStack(spacing: 6) {
                        Text("Estimated VO₂ Max").font(.caption).foregroundColor(.secondary)
                        Text(vo2 > 0 ? String(format: "%.1f", vo2) : "--")
                            .font(.system(size: 56, weight: .bold, design: .rounded))
                            .foregroundColor(.green)
                        Text("ml/kg/min").font(.caption).foregroundColor(.secondary)
                        Text("≈ 15.3 × (Max HR \(hrMax) ÷ Resting HR \(restingHR))")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 18)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.05)))

                    Stepper("Resting HR: \(restingHR) bpm", value: $restingHR, in: 30...110)
                        .padding(.horizontal, 4)

                    Button {
                        if vm.peakBpm > 0 { measuredMax = vm.peakBpm; useMeasuredMax = true }
                    } label: {
                        Label(vm.peakBpm > 0 ? "Use \(vm.peakBpm) bpm as my Max HR" : "No peak captured yet",
                              systemImage: "lock.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(.red).disabled(vm.peakBpm == 0)

                    if useMeasuredMax && measuredMax > 0 {
                        Text("✓ Zones now use your measured Max HR of \(measuredMax) bpm.")
                            .font(.caption).foregroundColor(.green)
                    }

                    HStack {
                        Button("Reset peak") { vm.resetPeak() }.buttonStyle(.bordered)
                        Spacer()
                        if vm.connected {
                            Button("Disconnect") { vm.disconnectStrap() }.buttonStyle(.bordered).tint(.gray)
                        } else {
                            Button("Connect strap") { vm.connect() }
                                .buttonStyle(.borderedProminent).tint(.red)
                                .disabled(!vm.bluetoothReady)
                        }
                    }

                    Text("VO₂ Max here is a rough estimate from the heart-rate-ratio method, not lab-measured. Push to true max only if you're healthy and cleared to.")
                        .font(.caption2).foregroundColor(.secondary)
                }
                .padding(18)
            }
        }
    }

    private func bigStat(title: String, value: String, unit: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.caption).foregroundColor(.secondary)
            Text(value).font(.system(size: 44, weight: .bold, design: .rounded))
                .monospacedDigit().foregroundColor(color)
            Text(unit).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.05)))
    }
}

// MARK: - Settings (formula → alert band)

struct SettingsView: View {
    @ObservedObject var vm: WorkoutViewModel
    @Binding var age: Int
    @Binding var isMale: Bool
    @Binding var weightKg: Double
    @Binding var restingHR: Int
    @Binding var lowZone: Int
    @Binding var highZone: Int
    @Binding var useMeasuredMax: Bool
    @Binding var measuredMax: Int

    var body: some View {
        NavigationView {
            Form {
                Section("You") {
                    Stepper("Age: \(age)", value: $age, in: 10...100)
                    Picker("Sex", selection: $isMale) {
                        Text("Male").tag(true); Text("Female").tag(false)
                    }
                    Stepper("Weight: \(Int(weightKg)) kg", value: $weightKg, in: 30...200)
                    Stepper("Resting HR: \(restingHR) bpm", value: $restingHR, in: 30...110)
                }

                Section {
                    Toggle("Use measured Max HR", isOn: $useMeasuredMax)
                    if useMeasuredMax {
                        Stepper("Measured Max HR: \(measuredMax) bpm", value: $measuredMax, in: 120...220)
                    }
                } header: {
                    Text("Max heart rate")
                } footer: {
                    Text(vm.usingMeasuredMax
                         ? "Using your measured Max HR of \(vm.mhr) bpm."
                         : "Formula: 220 − \(age) = \(vm.mhr) bpm. Turn on the toggle (or lock a value from the VO₂ Max tab) to use a measured max instead.")
                }

                Section {
                    Picker("Never drop below (floor)", selection: $lowZone) {
                        ForEach(Zones.all) { z in Text("Zone \(z.id) floor").tag(z.id) }
                    }
                    Picker("Never exceed (ceiling)", selection: $highZone) {
                        ForEach(Zones.all) { z in Text("Zone \(z.id) ceiling").tag(z.id) }
                    }
                } header: {
                    Text("Alert band")
                } footer: {
                    Text("With Max HR \(vm.mhr): you'll be alerted if you drop below \(vm.floorBpm) bpm (Zone \(lowZone) floor) or rise above \(vm.ceilingBpm) bpm (Zone \(highZone) ceiling).")
                }

                Section {
                    HStack {
                        Text("Stay below").foregroundColor(.secondary)
                        Spacer()
                        Text("\(vm.floorBpm)–\(vm.ceilingBpm) bpm").bold()
                    }
                    Button("Test alert") { vm.hrm.sendTestAlert() }
                } header: {
                    Text("Your target band")
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    ContentView()
}
