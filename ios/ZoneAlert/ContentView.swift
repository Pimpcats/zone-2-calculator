import SwiftUI
import UserNotifications
import UIKit
import StoreKit
import AVFoundation

// MARK: - App version info (auto-set by CI to 1.0.<build#>)

enum AppInfo {
    static var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
    }
    static var build: String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "0"
    }
}

// MARK: - Root (tabs + settings source of truth)

struct ContentView: View {
    @StateObject private var vm = WorkoutViewModel()
    @StateObject private var store = WorkoutStore()

    @AppStorage("age") private var age: Int = 40
    @AppStorage("isMale") private var isMale: Bool = true
    @AppStorage("weightLbs") private var weightLbs: Double = 165
    @AppStorage("restingHR") private var restingHR: Int = 60
    @AppStorage("bandZone") private var bandZone: Int = 2
    @AppStorage("customBand") private var customBand: Bool = false
    @AppStorage("floorBpmManual") private var floorBpmManual: Int = 114
    @AppStorage("ceilingBpmManual") private var ceilingBpmManual: Int = 133
    @AppStorage("useHRR") private var useHRR: Bool = false
    @AppStorage("voiceEnabled") private var voiceEnabled: Bool = false
    @AppStorage("voiceId") private var voiceId: String = ""
    @AppStorage("liveBanner") private var liveBanner: Bool = false
    @AppStorage("useMeasuredMax") private var useMeasuredMax: Bool = true
    @AppStorage("measuredMax") private var measuredMax: Int = 190
    @AppStorage("adaptiveHRV") private var adaptiveHRV: Bool = false
    @AppStorage("indoorMode") private var indoorMode: Bool = false
    @AppStorage("treadmillMph") private var treadmillMph: Double = 3.0

    var body: some View {
        TabView {
            WorkoutView(vm: vm, store: store)
                .tabItem { Label("Workout", systemImage: "figure.run") }
            VO2MaxView(vm: vm, restingHR: $restingHR,
                       useMeasuredMax: $useMeasuredMax, measuredMax: $measuredMax,
                       customBand: $customBand, floorBpmManual: $floorBpmManual,
                       ceilingBpmManual: $ceilingBpmManual)
                .tabItem { Label("VO2 Max", systemImage: "lungs.fill") }
            ProgressTabView(store: store)
                .tabItem { Label("Progress", systemImage: "chart.bar.fill") }
            SettingsView(vm: vm, hrm: vm.hrm, store: store, age: $age, isMale: $isMale, weightLbs: $weightLbs,
                         restingHR: $restingHR, bandZone: $bandZone, customBand: $customBand,
                         floorBpmManual: $floorBpmManual, ceilingBpmManual: $ceilingBpmManual,
                         useHRR: $useHRR, voiceEnabled: $voiceEnabled, voiceId: $voiceId, liveBanner: $liveBanner,
                         useMeasuredMax: $useMeasuredMax, measuredMax: $measuredMax)
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .tint(.red)
        .preferredColorScheme(.dark)
        .onAppear { vm.store = store; applySettings(); requestNotifications(); vm.loc.requestAuthorization() }
        .onChange(of: age) { _ in applySettings() }
        .onChange(of: isMale) { _ in applySettings() }
        .onChange(of: weightLbs) { _ in applySettings() }
        .onChange(of: restingHR) { _ in applySettings() }
        .onChange(of: bandZone) { _ in applySettings() }
        .onChange(of: customBand) { on in
            if on {   // prefill the manual fields from the current zone band
                floorBpmManual = Zones.lowerBpm(zone: bandZone, mhr: vm.mhr)
                ceilingBpmManual = Zones.upperBpm(zone: bandZone, mhr: vm.mhr)
            }
            applySettings()
        }
        .onChange(of: floorBpmManual) { _ in applySettings() }
        .onChange(of: ceilingBpmManual) { _ in applySettings() }
        .onChange(of: useHRR) { _ in applySettings() }
        .onChange(of: voiceEnabled) { _ in applySettings() }
        .onChange(of: voiceId) { _ in applySettings() }
        .onChange(of: adaptiveHRV) { _ in applySettings() }
        .onChange(of: indoorMode) { _ in applySettings() }
        .onChange(of: treadmillMph) { _ in applySettings() }
        .onChange(of: liveBanner) { _ in applySettings() }
        .onChange(of: useMeasuredMax) { _ in applySettings() }
        .onChange(of: measuredMax) { _ in applySettings() }
    }

    private func applySettings() {
        let override = (useMeasuredMax && measuredMax > 0) ? measuredMax : nil
        let mFloor = customBand ? floorBpmManual : nil
        let mCeil = customBand ? ceilingBpmManual : nil
        vm.apply(age: age, isMale: isMale, weightKg: weightLbs * 0.453592, restingHR: restingHR,
                 bandZone: bandZone, mhrOverride: override, manualFloor: mFloor, manualCeiling: mCeil,
                 useHRR: useHRR, adaptiveHRV: adaptiveHRV,
                 indoorMode: indoorMode, treadmillMph: treadmillMph)
        vm.hrm.voiceEnabled = voiceEnabled
        vm.hrm.voiceIdentifier = voiceId
        vm.liveBannerEnabled = liveBanner
        vm.syncLiveActivity()
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
    @State private var graphTab = 0
    @Environment(\.requestReview) private var requestReview
    @AppStorage("reviewAsked") private var reviewAsked = false
    @AppStorage("healthEnabled") private var healthEnabled = false
    @AppStorage("adaptiveHRV") private var adaptiveHRV = false
    @AppStorage("indoorMode") private var indoorMode = false
    @AppStorage("treadmillMph") private var treadmillMph: Double = 3.0

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
                        zoneIndicator
                        bandBar
                        adaptiveCard
                        indoorCard
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

    private var adaptiveCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $adaptiveHRV) {
                Label("Adaptive HRV zones", systemImage: "waveform.path.ecg")
                    .font(.subheadline.bold())
            }
            .tint(.green)
            Text(adaptiveDescription)
                .font(.caption2).foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
    }

    private var adaptiveDescription: String {
        if !adaptiveHRV {
            return "Off — zones use your Max HR formula. Turn on to auto-adjust your Zone 2 each day from your heart-rate variability (DFA-α1) while you train."
        }
        if vm.adaptiveThresholdHR > 0 {
            return "On — today's Zone 2 set from your HRV: ceiling \(vm.adaptiveThresholdHR) bpm (floor \(vm.floorBpm))."
        }
        return "On — reading your HRV during this workout to find today's threshold. Until it locks in, your Max-HR zones apply. Ramp effort up gradually for a clean read."
    }

    private var indoorCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $indoorMode) {
                Label("Indoor / treadmill", systemImage: "figure.walk.motion")
                    .font(.subheadline.bold())
            }
            .tint(.orange)
            if indoorMode {
                Stepper(value: $treadmillMph, in: 0.5...15, step: 0.1) {
                    HStack {
                        Text("Treadmill speed")
                        Spacer()
                        Text(String(format: "%.1f mph", treadmillMph))
                            .font(.callout.bold().monospacedDigit()).foregroundColor(.orange)
                    }
                }
                Text("Distance & pace come from this speed instead of GPS. Calories stay heart-rate based.")
                    .font(.caption2).foregroundColor(.secondary)
            } else {
                Text("Off — distance & pace use GPS (for outdoor walks/runs).")
                    .font(.caption2).foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
    }

    private var topBar: some View {
        HStack {
            Image(systemName: "heart.fill").foregroundColor(.red)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Workout").font(.headline.bold())
                    Text("v\(AppInfo.version)").font(.caption2).foregroundColor(.secondary)
                }
                Text(vm.connected ? vm.statusText : "Strap not connected")
                    .font(.caption2)
                    .foregroundColor(vm.connected ? .green : .secondary)
                    .lineLimit(1)
            }
            Spacer()
            if vm.duration > 0 {
                Button {
                    let record = vm.makeRecord()
                    store.add(record)
                    if healthEnabled { vm.health.save(record) }
                    vm.reset()
                    withAnimation { savedFlash = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation { savedFlash = false }
                    }
                    if store.records.count >= 2 && !reviewAsked {   // ask at a happy moment
                        reviewAsked = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { requestReview() }
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

    /// Color of the zone you're currently in (matches the in-app zone bands).
    private var zoneTint: Color {
        vm.currentZone >= 1 ? Zones.all[vm.currentZone - 1].color : Color(white: 0.6)
    }

    /// A badge at the top showing the current zone in its real color.
    private var zoneIndicator: some View {
        let z = vm.currentZone
        let name = z >= 1 ? Zones.all[z - 1].name : "Below Zone 1"
        return HStack(spacing: 8) {
            Circle().fill(zoneTint).frame(width: 12, height: 12)
            Text(z >= 1 ? "Zone \(z) · \(name)" : name)
                .font(.headline.bold()).foregroundColor(zoneTint)
            Spacer()
            Text(vm.bpm.map { "\($0) bpm" } ?? "-- bpm")
                .font(.subheadline.bold().monospacedDigit()).foregroundColor(zoneTint)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(zoneTint.opacity(0.15)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(zoneTint.opacity(0.5), lineWidth: 1))
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
                           valueColor: zoneTint)
            }
            MetricCell(icon: "timer", title: "Duration",
                       value: WorkoutViewModel.clock(vm.duration), unit: "")
        }
    }

    private var pager: some View {
        VStack(spacing: 8) {
            // Toggle instead of a swipe, so the graph can be scrolled without
            // accidentally flipping to the other view.
            Picker("", selection: $graphTab) {
                Text("Live zones").tag(0)
                Text("Time in zone").tag(1)
            }
            .pickerStyle(.segmented)

            if graphTab == 0 {
                ZoneGraphView(history: vm.hrHistory, mhr: vm.mhr, bpm: vm.bpm)
                    .frame(height: 240)
            } else {
                TimeInZoneView(timeInZone: vm.timeInZone, currentZone: vm.currentZone)
                    .frame(height: 240)
            }
        }
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
    @Binding var customBand: Bool
    @Binding var floorBpmManual: Int
    @Binding var ceilingBpmManual: Int

    private var hrMax: Int { vm.peakBpm > 0 ? vm.peakBpm : vm.mhr }
    private var vo2: Double { vm.vo2maxEstimate(usingMax: hrMax) }

    @State private var mode = 1
    @AppStorage("vo2IntervalSec") private var vo2IntervalSec = 30
    @AppStorage("vo2Rounds") private var vo2Rounds = 5

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    Picker("", selection: $mode) {
                        Text("Resting").tag(0)
                        Text("Max").tag(1)
                        Text("Threshold").tag(2)
                        Text("Recovery").tag(3)
                    }
                    .pickerStyle(.segmented)

                    switch mode {
                    case 0: restingContent
                    case 2: ownzoneContent
                    case 3: recoveryContent
                    default: testContent
                    }
                }
                .padding(18)
            }
        }
        // Resting test finished → adopt it as your resting HR (adaptive Zone 2).
        .onChange(of: vm.restingResult) { v in if v > 0 { restingHR = v } }
    }

    private var ownzoneContent: some View {
        VStack(spacing: 18) {
            Text("Adaptive Threshold (HRV)")
                .font(.title2.bold()).frame(maxWidth: .infinity, alignment: .leading)

            Text("A guided 5-minute ramp. The app reads your heart-rate variability and detects your aerobic threshold via DFA-α1 (the validated method) — α1 dropping through 0.75 marks the top of Zone 2 for today. Follow the stage prompts.")
                .font(.footnote).foregroundColor(.secondary)

            HStack(spacing: 10) {
                bigStat(title: "Heart rate", value: vm.bpm.map(String.init) ?? "--",
                        unit: "bpm", color: Color(red: 0.30, green: 0.66, blue: 1.0))
                bigStat(title: "DFA α1",
                        value: vm.ownzoneAlpha1 > 0 ? String(format: "%.2f", vm.ownzoneAlpha1) : "--",
                        unit: "≈0.75", color: .orange)
                bigStat(title: "RMSSD",
                        value: vm.ownzoneRMSSD > 0 ? String(format: "%.0f", vm.ownzoneRMSSD) : "--",
                        unit: "ms", color: .green)
            }

            if vm.ownzoneTesting { ownzoneRunning } else { ownzoneIdle }

            connectOnly

            Text("Needs a strap that sends R-R (HRV) data — most Bluetooth chest straps do. This is an experimental fitness estimate of your aerobic threshold, not a medical measurement.")
                .font(.caption2).foregroundColor(.secondary)
        }
    }

    // Live, staged ramp display while the test runs
    private var ownzoneRunning: some View {
        VStack(spacing: 10) {
            Text("Stage \(vm.ownzoneStageIndex + 1) of \(WorkoutViewModel.ownzoneStages.count)")
                .font(.caption).foregroundColor(.secondary)
            Text(vm.ownzoneStageLabel.uppercased())
                .font(.system(size: 30, weight: .heavy)).foregroundColor(.red)
            Text("\(WorkoutViewModel.clock(TimeInterval(vm.ownzoneStageRemaining))) left" +
                 (vm.ownzoneNextStageLabel.map { " · next: \($0)" } ?? " · final stage"))
                .font(.caption).foregroundColor(.secondary)

            // Per-stage progress
            ProgressView(value: Double(vm.ownzoneStageSeconds - vm.ownzoneStageRemaining),
                         total: Double(vm.ownzoneStageSeconds)).tint(.red)

            // Stage segments
            HStack(spacing: 4) {
                ForEach(0..<WorkoutViewModel.ownzoneStages.count, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(i < vm.ownzoneStageIndex ? Color.red.opacity(0.5)
                              : (i == vm.ownzoneStageIndex ? Color.red : Color.white.opacity(0.15)))
                        .frame(height: 8)
                }
            }

            Text("Total \(WorkoutViewModel.clock(TimeInterval(vm.ownzoneRemaining))) left")
                .font(.caption2).foregroundColor(.secondary)
            if vm.ownzoneThresholdHR > 0 {
                Text("Threshold detected: \(vm.ownzoneThresholdHR) bpm")
                    .font(.subheadline.bold()).foregroundColor(.green)
            }

            Button(role: .destructive) { vm.cancelOwnzoneTest() } label: {
                Label("Stop", systemImage: "stop.circle").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    // Pre-test: show the ramp plan + start
    private var ownzoneIdle: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("The 5-minute ramp").font(.caption.bold())
                ForEach(0..<WorkoutViewModel.ownzoneStages.count, id: \.self) { i in
                    let mins = WorkoutViewModel.ownzoneStages[0..<i].reduce(0) { $0 + $1.seconds } / 60
                    HStack {
                        Text(String(format: "%d:00", mins)).font(.caption.monospacedDigit())
                            .foregroundColor(.secondary).frame(width: 44, alignment: .leading)
                        Text(WorkoutViewModel.ownzoneStages[i].label).font(.caption)
                        Spacer()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))

            Button { vm.startOwnzoneTest() } label: {
                Label(vm.connected ? "Start guided test" : "Connect strap to start",
                      systemImage: "play.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(.red).disabled(!vm.connected)

            if vm.ownzoneThresholdHR > 0 {
                VStack(spacing: 8) {
                    Text("Aerobic threshold ≈ \(vm.ownzoneThresholdHR) bpm")
                        .font(.headline).foregroundColor(.green)
                    Button {
                        let top = vm.ownzoneThresholdHR
                        ceilingBpmManual = top
                        floorBpmManual = max(60, top - 15)
                        customBand = true
                    } label: {
                        Label("Use as today's Zone 2 (\(max(60, vm.ownzoneThresholdHR - 15))–\(vm.ownzoneThresholdHR))",
                              systemImage: "lock.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(.green)
                }
            }

        }
    }

    // Connect-only control (no Disconnect on this screen)
    private var connectOnly: some View {
        Group {
            if !vm.connected {
                Button { vm.connect() } label: {
                    Label("Connect strap", systemImage: "antenna.radiowaves.left.and.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(.red).disabled(!vm.bluetoothReady)
            }
        }
    }

    private var connectionControls: some View {
        Group {
            if vm.connected {
                Button { vm.disconnectStrap() } label: {
                    Label("Disconnect", systemImage: "xmark.circle").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).tint(.gray)
            } else {
                Button { vm.connect() } label: {
                    Label("Connect strap", systemImage: "antenna.radiowaves.left.and.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(.red)
                .disabled(!vm.bluetoothReady)
            }
        }
    }

    private var restingContent: some View {
        VStack(spacing: 18) {
            Text("Resting Heart Rate")
                .font(.title2.bold()).frame(maxWidth: .infinity, alignment: .leading)

            Text("Measures your resting heart rate — a key marker of fitness and recovery (generally, lower is fitter).")
                .font(.footnote).foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 6) {
                Image(systemName: "bed.double.fill").font(.title2).foregroundColor(.red)
                Text("Lay down, relax, and breathe normally for the full 5 minutes.")
                    .font(.subheadline).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity).padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))

            HStack(spacing: 14) {
                bigStat(title: "Current", value: vm.bpm.map(String.init) ?? "--",
                        unit: "bpm", color: Color(red: 0.30, green: 0.66, blue: 1.0))
                bigStat(title: vm.restingTesting ? "Lowest so far" : "Result",
                        value: restingDisplayValue, unit: "bpm", color: .green)
            }

            if vm.restingTesting {
                VStack(spacing: 4) {
                    Text("Time remaining").font(.caption).foregroundColor(.secondary)
                    Text(WorkoutViewModel.clock(TimeInterval(vm.restingRemaining)))
                        .font(.system(size: 44, weight: .bold, design: .rounded)).monospacedDigit()
                    ProgressView(value: Double(300 - vm.restingRemaining), total: 300).tint(.red)
                }
                Button(role: .destructive) { vm.cancelRestingTest() } label: {
                    Label("Cancel test", systemImage: "stop.circle").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            } else {
                Button {
                    vm.startRestingTest()
                } label: {
                    Label(vm.connected ? "Start 5-minute test" : "Connect strap to start",
                          systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(.red)
                .disabled(!vm.connected)

                if vm.restingResult > 0 {
                    Button {
                        restingHR = vm.restingResult
                    } label: {
                        Label("Use \(vm.restingResult) bpm as resting HR", systemImage: "lock.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(.green)
                }
            }

            Text("Current resting HR setting: \(restingHR) bpm")
                .font(.caption).foregroundColor(.secondary)

            connectionControls

            Text("Your resting HR feeds the VO₂ Max estimate on the Max Test tab.")
                .font(.caption2).foregroundColor(.secondary)
        }
    }

    private var restingDisplayValue: String {
        if vm.restingTesting { return vm.restingLow > 0 ? "\(vm.restingLow)" : "--" }
        return vm.restingResult > 0 ? "\(vm.restingResult)" : "--"
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

            // Natural flow: after you hit your max and stop, measure the recovery.
            Button {
                vm.startRecoveryTest()
                mode = 3
            } label: {
                Label("Just stopped? Measure recovery →", systemImage: "arrow.down.heart.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(.green)
            .disabled(!vm.connected || (vm.bpm ?? 0) == 0)

            HStack {
                Button("Reset peak") { vm.resetPeak() }.buttonStyle(.bordered)
                Spacer()
            }

            connectionControls

            Text("VO₂ Max here is a rough estimate from the heart-rate-ratio method, not lab-measured. Push to true max only if you're healthy and cleared to. After your max, hit Measure recovery to capture how fast your heart drops.")
                .font(.caption2).foregroundColor(.secondary)

            Divider().overlay(Color.white.opacity(0.1)).padding(.vertical, 4)
            Text("Interval training").font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            intervalWorkoutCard
            intervalTimerCard
        }
    }

    private var intervalWorkoutCard: some View {
        guideCard(title: "VO₂ intervals", icon: "stopwatch.fill") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Go hard (Zone 4–5, \(Int(Double(vm.mhr)*0.80))–\(vm.mhr) bpm) for the interval below, then ease off and let your heart rate fall back to Zone 2 (≤ \(vm.zone2Ceiling) bpm). If you recover within the interval time, you're ready to add 30 seconds.")
                HStack {
                    Text("Hard interval").font(.subheadline)
                    Spacer()
                    Text(intervalText).font(.title3.bold().monospacedDigit()).foregroundColor(.red)
                }
                Stepper("Adjust by 30s", value: $vo2IntervalSec, in: 30...900, step: 30)
            }
        }
    }

    private var intervalTimerCard: some View {
        guideCard(title: "Interval timer", icon: "timer") {
            if vm.intervalActive {
                VStack(spacing: 8) {
                    HStack {
                        Text(vm.intervalIsWork ? "GO HARD" : "RECOVER TO ZONE 2")
                            .font(.headline.bold())
                            .foregroundColor(vm.intervalIsWork ? .red : .green)
                        Spacer()
                        Text("Round \(vm.intervalRound)/\(vm.intervalTotalRounds)").font(.subheadline)
                    }
                    if vm.intervalIsWork {
                        Text(WorkoutViewModel.clock(TimeInterval(vm.intervalRemaining)))
                            .font(.system(size: 44, weight: .bold, design: .rounded)).monospacedDigit()
                            .frame(maxWidth: .infinity)
                        Text("Push hard until the timer hits zero.").font(.caption).foregroundColor(.secondary)
                    } else {
                        Text("\(vm.intervalRecoverElapsed)s")
                            .font(.system(size: 44, weight: .bold, design: .rounded)).monospacedDigit()
                            .frame(maxWidth: .infinity).foregroundColor(.green)
                        Text("Ease off — recovering until HR ≤ \(vm.zone2Ceiling). Beat the interval (\(intervalText)).")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Text("HR \(vm.bpm.map(String.init) ?? "--") bpm")
                        .font(.subheadline.bold()).foregroundColor(.secondary)
                    Button(role: .destructive) { vm.stopIntervals() } label: {
                        Label("Stop", systemImage: "stop.circle").frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    if vm.intervalHasResult { resultBanner }
                    Stepper("Rounds: \(vo2Rounds)", value: $vo2Rounds, in: 1...20)
                    Text("Each round: \(intervalText) hard, then recover to Zone 2 (≤ \(vm.zone2Ceiling) bpm). Needs the strap connected.")
                        .font(.caption).foregroundColor(.secondary)
                    Button {
                        vm.startIntervals(work: vo2IntervalSec, rounds: vo2Rounds)
                    } label: {
                        Label("Start VO₂ intervals", systemImage: "play.fill").frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent).tint(.red)
                    .disabled(!vm.connected)
                }
            }
        }
    }

    private var resultBanner: some View {
        let ok = vm.intervalRecoveredInTime
        return VStack(alignment: .leading, spacing: 6) {
            Text(ok ? "✓ Recovered in \(vm.intervalLastRecoverSec)s — under your \(intervalText) interval"
                    : "✗ Recovery took \(vm.intervalLastRecoverSec)s — longer than your \(intervalText) interval")
                .font(.subheadline.bold()).foregroundColor(ok ? .green : .orange)
            Text(ok ? "You're ready to step up." : "Keep this interval until you recover in time.")
                .font(.caption).foregroundColor(.secondary)
            if ok {
                Button { vo2IntervalSec = min(900, vo2IntervalSec + 30) } label: {
                    Label("Add 30s to the interval", systemImage: "plus.circle.fill").font(.caption)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill((ok ? Color.green : Color.orange).opacity(0.15)))
    }

    private var recoveryContent: some View {
        VStack(spacing: 18) {
            Text("Heart-Rate Recovery")
                .font(.title2.bold()).frame(maxWidth: .infinity, alignment: .leading)

            Text("How many beats your heart drops in 60 seconds right after hard effort — a strong fitness marker. Bigger drop = fitter. Go hard, stop, then tap Start the instant you stop and stay still.")
                .font(.footnote).foregroundColor(.secondary)

            HStack(spacing: 14) {
                bigStat(title: vm.recoveryTesting ? "At stop" : "Current",
                        value: vm.recoveryTesting ? "\(vm.recoveryStartHR)" : (vm.bpm.map(String.init) ?? "--"),
                        unit: "bpm", color: Color(red: 0.30, green: 0.66, blue: 1.0))
                bigStat(title: "Recovery (60s)",
                        value: vm.recoveryResult > 0 ? "−\(vm.recoveryResult)" : "--",
                        unit: "bpm", color: .green)
            }

            if vm.recoveryTesting {
                VStack(spacing: 4) {
                    Text("Stay still — measuring").font(.caption).foregroundColor(.secondary)
                    Text(WorkoutViewModel.clock(TimeInterval(vm.recoveryRemaining)))
                        .font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit()
                    ProgressView(value: Double(60 - vm.recoveryRemaining), total: 60).tint(.red)
                    Text("Now: \(vm.bpm.map(String.init) ?? "--") bpm").font(.caption)
                }
                Button(role: .destructive) { vm.cancelRecoveryTest() } label: {
                    Label("Cancel", systemImage: "stop.circle").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            } else {
                Button { vm.startRecoveryTest() } label: {
                    Label(vm.connected ? "Start (I just stopped)" : "Connect strap to start",
                          systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(.red)
                .disabled(!vm.connected || (vm.bpm ?? 0) == 0)
                if vm.recoveryResult > 0 {
                    Text("Your heart dropped \(vm.recoveryResult) bpm in the first minute.")
                        .font(.caption).foregroundColor(.green)
                }
            }

            connectionControls

            Text("Rough guide: a 1-minute recovery above ~12 bpm is typical; higher is better. Tracked on the Progress trends. Not a medical measurement.")
                .font(.caption2).foregroundColor(.secondary)
        }
    }

    private var intervalText: String {
        String(format: "%d:%02d", vo2IntervalSec / 60, vo2IntervalSec % 60)
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
    @ObservedObject var hrm: HeartRateManager
    @ObservedObject var store: WorkoutStore
    @Binding var age: Int
    @Binding var isMale: Bool
    @Binding var weightLbs: Double
    @Binding var restingHR: Int
    @Binding var bandZone: Int
    @Binding var customBand: Bool
    @Binding var floorBpmManual: Int
    @Binding var ceilingBpmManual: Int
    @Binding var useHRR: Bool
    @Binding var voiceEnabled: Bool
    @Binding var voiceId: String
    @Binding var liveBanner: Bool
    @Binding var useMeasuredMax: Bool
    @Binding var measuredMax: Int

    @State private var showNotifDenied = false
    @State private var exportItems: ExportItems?
    @State private var showCompat = false
    @State private var showZoneChart = true
    @AppStorage("healthEnabled") private var healthEnabled = false

    /// One zone's row in the collapsible chart — live bpm range from the current Max HR.
    private func zoneRow(_ z: Zone) -> some View {
        let lo = Int(Double(vm.mhr) * z.low)
        let hi = Int(Double(vm.mhr) * z.high)
        let current = vm.connected && vm.currentZone == z.id
        return HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3).fill(z.color).frame(width: 6, height: 32)
            Text("Z\(z.id)").font(.headline).foregroundColor(z.color).frame(width: 30, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(z.name).font(.callout)
                Text("\(Int(z.low * 100))–\(Int(z.high * 100))% of Max").font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(lo)–\(hi)").font(.callout.bold().monospacedDigit())
                Text("bpm").font(.caption2).foregroundColor(.secondary)
            }
        }
        .listRowBackground(current ? z.color.opacity(0.18) : Color(white: 0.12))
    }

    private func intRow(_ label: String, value: Binding<Int>, unit: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            NumberField(value: value).frame(width: 72)
            Text(unit).foregroundColor(.secondary)
        }
    }

    /// English voices installed on this device, best quality first.
    private var englishVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .sorted {
                $0.quality.rawValue != $1.quality.rawValue
                    ? $0.quality.rawValue > $1.quality.rawValue   // Premium/Enhanced first
                    : $0.name < $1.name
            }
    }

    private func voiceLabel(_ v: AVSpeechSynthesisVoice) -> String {
        let q = v.quality == .premium ? "Premium" : (v.quality == .enhanced ? "Enhanced" : "Default")
        return "\(v.name) · \(q) (\(v.language))"
    }

    private var voicePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Voice", selection: $voiceId) {
                Text("System default").tag("")
                ForEach(englishVoices, id: \.identifier) { v in
                    Text(voiceLabel(v)).tag(v.identifier)
                }
            }
            .pickerStyle(.menu)

            Button {
                vm.hrm.voiceIdentifier = voiceId
                vm.hrm.say("This is your zone alert voice. You're in zone two.")
            } label: {
                Label("Preview voice", systemImage: "speaker.wave.2.fill")
            }

            Text("Want more natural voices? Download them in iOS Settings → Accessibility → Spoken Content → Voices → English (look for “Enhanced” or “Premium”). They'll appear in this list.")
                .font(.caption2).foregroundColor(.secondary)
        }
    }

    private var bandFooter: String {
        if customBand {
            return "Alerts if you drop below \(vm.floorBpm) or rise above \(vm.ceilingBpm) bpm."
        }
        let pctLo = Zones.lowerBpm(zone: bandZone, mhr: vm.mhr)
        let pctHi = Zones.upperBpm(zone: bandZone, mhr: vm.mhr)
        let karLo = Zones.lowerBpmHRR(zone: bandZone, mhr: vm.mhr, rest: vm.restingHR)
        let karHi = Zones.upperBpmHRR(zone: bandZone, mhr: vm.mhr, rest: vm.restingHR)
        if useHRR {
            return "Karvonen (Heart-Rate Reserve): Zone \(bandZone) = \(karLo)–\(karHi) bpm, from Max HR \(vm.mhr) and resting HR \(vm.restingHR). (Plain % of Max would be \(pctLo)–\(pctHi).) It accounts for your fitness and shifts as your resting HR changes — run the Resting test to refresh it."
        }
        return "% of Max HR: Zone \(bandZone) = \(pctLo)–\(pctHi) bpm. Switch to Karvonen and it becomes \(karLo)–\(karHi) bpm (factors in your resting HR — usually a better fit)."
    }

    var body: some View {
        NavigationView {
            Form {
                Section("You") {
                    intRow("Age", value: $age, unit: "yrs")
                    Picker("Sex", selection: $isMale) {
                        Text("Male").tag(true); Text("Female").tag(false)
                    }
                    HStack {
                        Text("Weight")
                        Spacer()
                        NumberField(value: Binding(
                            get: { Int(weightLbs.rounded()) },
                            set: { weightLbs = Double($0) }))
                            .frame(width: 72)
                        Text("lbs").foregroundColor(.secondary)
                    }
                    intRow("Resting HR", value: $restingHR, unit: "bpm")
                }

                Section {
                    Toggle("Use measured Max HR", isOn: $useMeasuredMax)
                    if useMeasuredMax {
                        intRow("Max HR", value: $measuredMax, unit: "bpm")
                    }
                    DisclosureGroup("Heart-rate zones", isExpanded: $showZoneChart) {
                        ForEach(Array(Zones.all.reversed())) { z in zoneRow(z) }
                    }
                } header: {
                    Text("Max heart rate")
                } footer: {
                    Text(vm.usingMeasuredMax
                         ? "Using your measured Max HR of \(vm.mhr) bpm — every zone above updates live as you change it."
                         : "Formula: 220 − \(age) = \(vm.mhr) bpm. Turn on the toggle (or lock a value from the VO₂ Max tab) to use a measured max instead. The zones above update live as Max HR changes.")
                }

                Section {
                    Toggle("Set band manually (bpm)", isOn: $customBand)
                    if customBand {
                        intRow("Don't drop below", value: $floorBpmManual, unit: "bpm")
                        intRow("Don't exceed", value: $ceilingBpmManual, unit: "bpm")
                    } else {
                        Picker("Stay in zone", selection: $bandZone) {
                            ForEach(Zones.all) { z in Text("Zone \(z.id) · \(z.name)").tag(z.id) }
                        }
                        Picker("Zone math", selection: $useHRR) {
                            Text("% of Max HR").tag(false)
                            Text("Karvonen (HR Reserve)").tag(true)
                        }
                    }
                } header: {
                    Text("Alert band")
                } footer: {
                    Text(bandFooter)
                }

                Section {
                    HStack {
                        Text("Paired strap").foregroundColor(.secondary)
                        Spacer()
                        Text(hrm.pinnedName ?? "Not paired yet")
                            .bold().foregroundColor(hrm.pinnedName == nil ? .secondary : .primary)
                    }
                    if hrm.connected, let n = hrm.deviceName {
                        Text("Connected to \(n)").font(.caption).foregroundColor(.green)
                    }
                    if hrm.pinnedName != nil {
                        if hrm.pinnedRRSupported {
                            Label("Tested compatible · HR + HRV ✓", systemImage: "checkmark.seal.fill")
                                .font(.caption).foregroundColor(.green)
                        } else {
                            Label("HR ✓ · HRV not confirmed yet", systemImage: "checkmark.circle")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                    Button(role: .destructive) { hrm.forgetDevice() } label: {
                        Label("Forget / re-pair strap", systemImage: "xmark.circle")
                    }
                    .disabled(hrm.pinnedID == nil)
                    Button { showCompat = true } label: {
                        Label("Scan for compatible sensors", systemImage: "dot.radiowaves.left.and.right")
                    }
                    if hrm.demoMode {
                        Button(role: .destructive) { hrm.stopDemo() } label: {
                            Label("Stop demo", systemImage: "stop.circle")
                        }
                    } else {
                        Button { hrm.startDemo() } label: {
                            Label("Demo mode (no strap needed)", systemImage: "play.circle")
                        }
                    }
                } header: {
                    Text("Heart rate strap")
                } footer: {
                    Text("Once paired, Zone Alert only ever connects to this exact strap and ignores every other heart-rate device nearby. Forget it to switch straps (pair the new one while only it is awake).")
                }

                Section {
                    Button {
                        let urls = ZoneExport.generate(vm: vm, store: store)
                        if !urls.isEmpty { exportItems = ExportItems(urls: urls) }
                    } label: {
                        Label("Export all data", systemImage: "square.and.arrow.up")
                    }
                    Toggle("Save workouts to Apple Health", isOn: $healthEnabled)
                        .onChange(of: healthEnabled) { on in
                            if on {
                                vm.health.requestAuth { granted in if !granted { healthEnabled = false } }
                            }
                        }
                } header: {
                    Text("Data")
                } footer: {
                    Text("Exports everything: a clean PDF report (profile, zones, VO₂, trends, workouts, weight & calories) with a final page of raw flat numbers, plus your threshold-test CSVs. Opens the share sheet to save or send. Apple Health saving requires a signed build (App Store/TestFlight).")
                }

                Section("About") {
                    HStack {
                        Text("Version").foregroundColor(.secondary)
                        Spacer()
                        Text("\(AppInfo.version) (build \(AppInfo.build))").bold().monospacedDigit()
                    }
                }

                Section {
                    Text("Zone Alert is a fitness training aid, not a medical device. It does not diagnose, treat, cure, or monitor any medical condition, and its heart-rate, VO₂, threshold, and calorie figures are estimates. Consult a physician before beginning intense exercise or relying on any reading. Stop exercising and seek help if you feel chest pain, dizziness, or faintness.")
                        .font(.caption2).foregroundColor(.secondary)
                } header: {
                    Text("Health & safety")
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
                    Toggle("Speak alerts (voice cues)", isOn: $voiceEnabled)
                    if voiceEnabled { voicePicker }
                    Toggle("Live heart-rate banner while working out (Lock Screen / Dynamic Island)", isOn: $liveBanner)
                    Button {
                        vm.runTestAlert(onDenied: { showNotifDenied = true })
                    } label: {
                        Label("Test alert (buzz + banner)", systemImage: "bell.badge")
                    }
                    Button {
                        vm.hrm.scheduleBackgroundTest()
                    } label: {
                        Label("Test background alert (lock screen in 6s)", systemImage: "lock.iphone")
                    }
                } header: {
                    Text("Your target band")
                } footer: {
                    Text("Tip: tap the background test, then immediately lock your phone — a banner should appear in ~6 seconds. While a strap is connected (or Demo mode is on), Zone Alert keeps running in the background so zone alerts reach you with the screen locked.")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
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
            .sheet(item: $exportItems) { ActivityView(items: $0.urls) }
            .sheet(isPresented: $showCompat) {
                CompatView(hrm: hrm)
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

                    DayReviewView(store: store)

                    HStack(spacing: 14) {
                        totalsCard(title: "Today", t: store.todayTotals)
                        totalsCard(title: "This week", t: store.weekTotals)
                    }

                    weeklyChart

                    if !store.series("resting").isEmpty || !store.series("ownzone").isEmpty || !store.series("recovery").isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Trends").font(.headline)
                            if !store.series("resting").isEmpty {
                                TrendChart(title: "Resting HR",
                                           points: store.series("resting"), color: .green)
                            }
                            if !store.series("ownzone").isEmpty {
                                TrendChart(title: "Aerobic threshold",
                                           points: store.series("ownzone"), color: .orange)
                            }
                            if !store.series("recovery").isEmpty {
                                TrendChart(title: "HR recovery (60s drop)",
                                           points: store.series("recovery"), color: .mint)
                            }
                        }
                    }

                    if store.records.isEmpty {
                        Text("No workouts saved yet. Finish a workout (tap Finish on the Workout tab) and it'll show up here.")
                            .font(.caption).foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Recent workouts").font(.headline)
                            Text("Swipe a workout right to delete it.")
                                .font(.caption2).foregroundColor(.secondary)
                            ForEach(store.records.prefix(20)) { r in
                                RecentWorkoutRow(record: r) { store.delete(r) }
                            }
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

}

/// A small line chart of a measurement series over time (resting HR / threshold).
struct TrendChart: View {
    let title: String
    let points: [Measurement]   // oldest → newest
    let color: Color

    var body: some View {
        let vals = points.map { Double($0.bpm) }
        let minV = vals.min() ?? 0
        let maxV = vals.max() ?? 1
        let range = max(maxV - minV, 1)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.subheadline.bold())
                Spacer()
                if let last = points.last { Text("\(last.bpm) bpm").bold().foregroundColor(color) }
            }
            if vals.count > 1, let first = vals.first, let last = vals.last {
                let delta = Int(last - first)
                Text("\(delta >= 0 ? "▲" : "▼") \(abs(delta)) bpm over \(vals.count) tests")
                    .font(.caption2).foregroundColor(.secondary)
            } else {
                Text("Run more tests to see the trend").font(.caption2).foregroundColor(.secondary)
            }
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                ZStack {
                    Path { p in
                        for (i, v) in vals.enumerated() {
                            let x = vals.count > 1 ? w * CGFloat(i) / CGFloat(vals.count - 1) : w / 2
                            let y = h - CGFloat((v - minV) / range) * h
                            if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                            else { p.addLine(to: CGPoint(x: x, y: y)) }
                        }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                    ForEach(vals.indices, id: \.self) { i in
                        let x = vals.count > 1 ? w * CGFloat(i) / CGFloat(vals.count - 1) : w / 2
                        let y = h - CGFloat((vals[i] - minV) / range) * h
                        Circle().fill(color).frame(width: 5, height: 5).position(x: x, y: y)
                    }
                }
            }
            .frame(height: 90)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
    }
}

/// A recent-workout row with a custom swipe-right-to-delete gesture:
/// swipe right to reveal Delete (tap it), or keep swiping to confirm.
struct RecentWorkoutRow: View {
    let record: WorkoutRecord
    let onDelete: () -> Void

    @State private var offset: CGFloat = 0
    @State private var base: CGFloat = 0
    private let revealWidth: CGFloat = 96

    var body: some View {
        ZStack(alignment: .leading) {
            Button { confirmDelete() } label: {
                Label("Delete", systemImage: "trash")
                    .font(.callout.bold())
                    .foregroundColor(.white)
                    .frame(width: revealWidth)
                    .frame(maxHeight: .infinity)
                    .background(Color.red)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .opacity(offset > 4 ? 1 : 0)

            content
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.11)))
                .offset(x: offset)
                .gesture(
                    DragGesture(minimumDistance: 14)
                        .onChanged { v in
                            offset = min(max(0, base + v.translation.width), 230)
                        }
                        .onEnded { v in
                            let x = base + v.translation.width
                            if x > 190 {
                                confirmDelete()
                            } else if x > 55 {
                                base = revealWidth
                                withAnimation(.spring(response: 0.3)) { offset = revealWidth }
                            } else {
                                base = 0
                                withAnimation(.spring(response: 0.3)) { offset = 0 }
                            }
                        }
                )
        }
    }

    private var content: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(record.date, format: .dateTime.weekday().month().day().hour().minute())
                    .font(.callout.bold())
                Text("\(WorkoutViewModel.clock(record.duration)) · \(String(format: "%.2f mi", record.distanceMiles)) · avg \(record.avgBpm) bpm")
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Text("\(Int(record.calories)) kcal").font(.caption.bold())
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func confirmDelete() {
        withAnimation(.easeIn(duration: 0.2)) { offset = 420 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { onDelete() }
    }
}

#Preview {
    ContentView()
}
