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
                    Text("Any device listed here works with Zone Alert. Tap “Use this strap” to pair it — Zone Alert will then always reconnect to it automatically. “Check R-R” confirms HRV support for the adaptive threshold features; wear the strap with wet contacts while it checks.")
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
                if d.testing {
                    Text("Checking HRV… keep the strap on").font(.caption).foregroundColor(.secondary)
                } else if let rr = d.rrSupported {
                    Text(rr ? "HRV / R-R ✓ — adaptive threshold supported"
                            : "No R-R seen yet — wet the contacts, wear it snugly, then Retry")
                        .font(.caption).foregroundColor(rr ? .green : .orange)
                } else {
                    Text("Signal \(d.rssi) dBm").font(.caption2).foregroundColor(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                if hrm.pinnedID == d.id.uuidString {
                    Label("Paired", systemImage: "checkmark.circle.fill")
                        .font(.caption.bold()).foregroundColor(.green)
                } else {
                    Button("Use this strap") { hrm.pair(id: d.id); dismiss() }
                        .buttonStyle(.borderedProminent).font(.caption)
                }
                if d.testing {
                    ProgressView()
                } else if d.rrSupported == true {
                    Image(systemName: "checkmark.seal.fill").foregroundColor(.green)
                } else {
                    Button(d.rrSupported == nil ? "Check R-R" : "Retry R-R") { hrm.testRR(id: d.id) }
                        .buttonStyle(.bordered).font(.caption)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
