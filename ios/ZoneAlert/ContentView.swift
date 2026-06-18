import SwiftUI
import UserNotifications

// MARK: - Root (tabs + settings source of truth)

struct ContentView: View {
    @StateObject private var vm = WorkoutViewModel()
    @StateObject private var store = WorkoutStore()

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
            WorkoutView(vm: vm, store: store)
                .tabItem { Label("Workout", systemImage: "figure.run") }
            CalculatorView(vm: vm)
                .tabItem { Label("Zones", systemImage: "list.bullet.rectangle") }
            VO2MaxView(vm: vm, restingHR: $restingHR,
                       useMeasuredMax: $useMeasuredMax, measuredMax: $measuredMax)
                .tabItem { Label("VO2 Max", systemImage: "lungs.fill") }
            ProgressTabView(store: store)
                .tabItem { Label("Progress", systemImage: "chart.bar.fill") }
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
    @ObservedObject var store: WorkoutStore
    @State private var savedFlash = false

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

            if savedFlash {
                Text("Workout saved ✓")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(Capsule().fill(Color.green))
                    .foregroundColor(.black)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 60)
                    .frame(maxHeight: .infinity, alignment: .top)
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
            if vm.duration > 0 {
                Button {
                    store.add(vm.makeRecord())
                    vm.reset()
                    withAnimation { savedFlash = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation { savedFlash = false }
                    }
                } label: {
                    Label("Finish", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.bold())
                        .foregroundColor(.green)
                }
            }
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

    @State private var mode = 0
    @AppStorage("vo2IntervalSec") private var vo2IntervalSec = 120

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    Picker("", selection: $mode) {
                        Text("Test").tag(0)
                        Text("Guide").tag(1)
                    }
                    .pickerStyle(.segmented)

                    if mode == 0 { testContent } else { guideContent }
                }
                .padding(18)
            }
        }
    }

    private var testContent: some View {
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
    }

    private var intervalText: String {
        String(format: "%d:%02d", vo2IntervalSec / 60, vo2IntervalSec % 60)
    }

    private var guideContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("VO₂ Max — the simple version")
                .font(.title2.bold())

            guideCard(title: "What it is", icon: "lungs.fill") {
                Text("VO₂ max is the most oxygen your body can use when working flat-out. It's the single best number for aerobic fitness — the higher it is, the longer and harder you can go.")
            }

            guideCard(title: "How to test your max HR", icon: "bolt.heart.fill") {
                VStack(alignment: .leading, spacing: 6) {
                    bullet("1.", "Warm up easy for 10 minutes.")
                    bullet("2.", "Every minute, increase the effort (run/bike faster or steeper).")
                    bullet("3.", "Final 1–2 minutes: go all-out until you truly can't hold pace.")
                    bullet("4.", "Watch the Test tab — your highest reading is your peak.")
                    bullet("5.", "Tap “Use … as my Max HR” to lock it into your zones.")
                }
            }

            guideCard(title: "Your VO₂ workout", icon: "stopwatch.fill") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Do hard intervals at Zone 4–5 (\(Int(Double(vm.mhr)*0.80))–\(vm.mhr) bpm), with an equal easy recovery, 4–6 times. Each week (or every other week) add 30 seconds to the hard interval.")
                    HStack {
                        Text("This block's hard interval").font(.subheadline)
                        Spacer()
                        Text(intervalText).font(.title3.bold().monospacedDigit()).foregroundColor(.red)
                    }
                    Stepper("Adjust by 30s", value: $vo2IntervalSec, in: 30...900, step: 30)
                    Text("Recovery: same as the interval (\(intervalText)) easy. Bump +30s when this feels repeatable.")
                        .font(.caption).foregroundColor(.secondary)
                }
            }

            guideCard(title: "Example progression", icon: "chart.line.uptrend.xyaxis") {
                VStack(alignment: .leading, spacing: 4) {
                    bullet("Wk 1–2", "4 × 2:00 hard / 2:00 easy")
                    bullet("Wk 3–4", "4 × 2:30 hard / 2:30 easy")
                    bullet("Wk 5–6", "5 × 3:00 hard / 3:00 easy")
                    bullet("Then", "keep adding 30s, or add a rep.")
                }
            }

            Text("Push to true max only if you're healthy and cleared for hard exercise. Stop if you feel chest pain, dizziness, or faintness.")
                .font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func guideCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.headline).foregroundColor(.red)
            content().font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
    }

    private func bullet(_ lead: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(lead).font(.subheadline.bold()).foregroundColor(.secondary).frame(width: 46, alignment: .leading)
            Text(text).font(.subheadline)
            Spacer(minLength: 0)
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

    @State private var showNotifDenied = false

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
                        Text("Stay between").foregroundColor(.secondary)
                        Spacer()
                        Text("\(vm.floorBpm)–\(vm.ceilingBpm) bpm").bold()
                    }
                    HStack {
                        Text("Notifications").foregroundColor(.secondary)
                        Spacer()
                        Text(vm.notifStatus)
                            .foregroundColor(vm.notifStatus == "On" ? .green : .orange)
                    }
                    Button {
                        vm.runTestAlert(onDenied: { showNotifDenied = true })
                    } label: {
                        Label("Test alert (buzz + banner)", systemImage: "bell.badge")
                    }
                } header: {
                    Text("Your target band")
                } footer: {
                    Text("Tip: you'll feel a buzz immediately. The banner/sound shows here and on your lock screen. If it says Notifications: Off, tap Test and choose Open Settings → turn on Allow Notifications.")
                }
            }
            .navigationTitle("Settings")
            .onAppear { vm.refreshNotifStatus() }
            .alert("Turn on notifications", isPresented: $showNotifDenied) {
                Button("Open Settings") { vm.openSystemSettings() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Notifications are turned off for Zone Alert, so zone alerts can't show. Open Settings → Notifications → allow them, then try the test again.")
            }
        }
    }
}

// MARK: - Zone 2 calculator

struct CalculatorView: View {
    @ObservedObject var vm: WorkoutViewModel

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 4) {
                        Text("Heart-Rate Zones").font(.title2.bold())
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(vm.usingMeasuredMax
                             ? "Measured Max HR: \(vm.mhr) bpm"
                             : "Max HR = 220 − age = \(vm.mhr) bpm")
                            .font(.subheadline).foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    ForEach(Zones.all) { z in
                        let lo = Int(Double(vm.mhr) * z.low)
                        let hi = Int(Double(vm.mhr) * z.high)
                        let current = vm.connected && vm.currentZone == z.id
                        HStack(spacing: 14) {
                            Text("Z\(z.id)")
                                .font(.title3.bold()).foregroundColor(z.color)
                                .frame(width: 42)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(z.name).font(.callout.bold())
                                Text("\(Int(z.low*100))–\(Int(z.high*100))% of Max HR")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 0) {
                                Text("\(lo)–\(hi)").font(.title3.bold().monospacedDigit())
                                Text("bpm").font(.caption2).foregroundColor(.secondary)
                            }
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 12)
                            .fill(z.color.opacity(current ? 0.25 : 0.10)))
                        .overlay(RoundedRectangle(cornerRadius: 12)
                            .stroke(z.color, lineWidth: current ? 2 : 0))
                    }

                    Text("Zone 2 (\(Int(Double(vm.mhr)*0.60))–\(Int(Double(vm.mhr)*0.70)) bpm) is your aerobic base. Adjust age / Max HR in Settings.")
                        .font(.caption).foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(18)
            }
        }
    }
}

// MARK: - Progress (daily / weekly)

struct ProgressTabView: View {
    @ObservedObject var store: WorkoutStore

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    Text("Progress").font(.title2.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 14) {
                        totalsCard(title: "Today", t: store.todayTotals)
                        totalsCard(title: "This week", t: store.weekTotals)
                    }

                    weeklyChart

                    if store.records.isEmpty {
                        Text("No workouts saved yet. Finish a workout (tap Finish on the Workout tab) and it'll show up here.")
                            .font(.caption).foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Recent workouts").font(.headline)
                            ForEach(store.records.prefix(20)) { r in recentRow(r) }
                        }
                    }
                }
                .padding(18)
            }
        }
    }

    private func totalsCard(title: String, t: ProgressTotals) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.bold()).foregroundColor(.red)
            row("Workouts", "\(t.count)")
            row("Time", WorkoutViewModel.clock(t.duration))
            row("Distance", String(format: "%.2f mi", t.miles))
            row("Calories", "\(Int(t.calories)) kcal")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(.caption).foregroundColor(.secondary)
            Spacer()
            Text(v).font(.callout.bold().monospacedDigit())
        }
    }

    private var weeklyChart: some View {
        let data = store.last7DaysMinutes()
        let maxV = max(data.map { $0.minutes }.max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Last 7 days (minutes)").font(.caption).foregroundColor(.secondary)
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(data.indices, id: \.self) { i in
                    let d = data[i]
                    VStack(spacing: 4) {
                        Text(d.minutes > 0 ? "\(Int(d.minutes))" : "")
                            .font(.caption2).foregroundColor(.secondary)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.red.opacity(d.minutes > 0 ? 0.9 : 0.25))
                            .frame(height: max(4, CGFloat(d.minutes / maxV) * 110))
                        Text(d.label).font(.caption2).foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 150)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
    }

    private func recentRow(_ r: WorkoutRecord) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(r.date, format: .dateTime.weekday().month().day().hour().minute())
                    .font(.callout.bold())
                Text("\(WorkoutViewModel.clock(r.duration)) · \(String(format: "%.2f mi", r.distanceMiles)) · avg \(r.avgBpm) bpm")
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Text("\(Int(r.calories)) kcal").font(.caption.bold())
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.04)))
        .contextMenu { Button(role: .destructive) { store.delete(r) } label: { Label("Delete", systemImage: "trash") } }
    }
}

#Preview {
    ContentView()
}
