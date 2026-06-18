import SwiftUI

/// Scans for nearby Bluetooth heart-rate sensors and reports, per device,
/// whether it exposes the standard HR service and R-R (HRV / OwnZone) data.
struct CompatView: View {
    @ObservedObject var hrm: HeartRateManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                Section {
                    if hrm.compatDevices.isEmpty {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Scanning… make sure your sensor is awake (chest straps: moisten the strap and put it on).")
                                .font(.callout).foregroundColor(.secondary)
                        }
                    } else {
                        ForEach(hrm.compatDevices) { d in row(d) }
                    }
                } header: {
                    Text("Nearby heart-rate sensors")
                } footer: {
                    Text("Any device listed here exposes the standard Bluetooth Heart Rate service, so it works with Zone Alert. Tap “Check R-R” to confirm HRV support for the adaptive threshold features (chest straps usually pass).")
                }
            }
            .navigationTitle("Compatibility")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { hrm.stopCompatScan(); dismiss() }
                }
            }
            .onAppear { hrm.startCompatScan() }
            .onDisappear { hrm.stopCompatScan() }
        }
    }

    private func row(_ d: CompatDevice) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(d.name).font(.callout.bold())
                Text("❤️ Heart rate ✓").font(.caption).foregroundColor(.green)
                if let rr = d.rrSupported {
                    Text(rr ? "HRV / R-R ✓ — adaptive threshold supported"
                            : "HRV / R-R ✗ — HR works, threshold features won't")
                        .font(.caption).foregroundColor(rr ? .green : .orange)
                } else {
                    Text("Signal \(d.rssi) dBm").font(.caption2).foregroundColor(.secondary)
                }
            }
            Spacer()
            if d.testing {
                ProgressView()
            } else if d.rrSupported == nil {
                Button("Check R-R") { hrm.testRR(id: d.id) }
                    .buttonStyle(.bordered).font(.caption)
            } else {
                Image(systemName: d.rrSupported == true ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(d.rrSupported == true ? .green : .orange)
            }
        }
        .padding(.vertical, 2)
    }
}
