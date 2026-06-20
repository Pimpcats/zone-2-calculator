import SwiftUI

/// All-day data (steps, active calories, resting HR, sleep) brought in from Apple
/// Health via the **Shortcuts bridge** — no HealthKit entitlement needed, so it works
/// on a free sideloaded build. Kept separate from the H9 workout data.
struct AppleHealthView: View {
    @ObservedObject var store: HealthImportStore
    @State private var showSetup = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    Text("Health").font(.largeTitle.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("Your daily steps, resting heart rate, and sleep — imported from Apple Health. Kept completely separate from your H9 workout data.")
                        .font(.subheadline).foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let d = store.today {
                        todayCard(d)
                    } else {
                        emptyCard
                    }

                    if store.days.count > 1 {
                        recentList
                    }

                    setupSection
                }
                .padding(20)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func todayCard(_ d: DailyHealth) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today").font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                stat("Steps", d.steps > 0 ? "\(d.steps)" : "—", "figure.walk")
                stat("Active", d.activeCalories > 0 ? "\(d.activeCalories)" : "—", "flame.fill", unit: "kcal")
                stat("Resting HR", d.restingHR > 0 ? "\(d.restingHR)" : "—", "heart.fill", unit: "bpm")
                stat("Sleep", d.sleepMinutes > 0 ? "\(d.sleepMinutes / 60)h \(d.sleepMinutes % 60)m" : "—", "bed.double.fill")
            }
        }
    }

    private var emptyCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.and.arrow.down").font(.title)
            Text("No data imported yet").font(.subheadline.bold())
            Text("Set up the one-time Shortcut below to pull today's numbers from Apple Health.")
                .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 22)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
    }

    private var recentList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recent days").font(.headline)
            ForEach(store.days.prefix(14)) { h in
                HStack {
                    Text(h.date?.formatted(.dateTime.weekday(.abbreviated).month().day()) ?? h.dateKey)
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

    private var setupSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { withAnimation { showSetup.toggle() } } label: {
                HStack {
                    Label("How to set up the import Shortcut", systemImage: "wand.and.stars")
                        .font(.subheadline.bold())
                    Spacer()
                    Image(systemName: showSetup ? "chevron.up" : "chevron.down")
                }
                .foregroundColor(.primary)
            }
            .buttonStyle(.plain)

            if showSetup {
                VStack(alignment: .leading, spacing: 8) {
                    step("1", "Open the Apple **Shortcuts** app → **+** to create a new shortcut.")
                    step("2", "Add **Find Health Samples** → Sample Type **Steps**, filter **Start Date is Today**.")
                    step("3", "Add **Calculate Statistics** → **Sum** of those samples. Tap the result → **Rename** to *Steps*.")
                    step("4", "Repeat for **Resting Heart Rate** (use **Average**, name it *RestingHR*) and **Active Energy** (**Sum**, name it *Active*).")
                    step("5", "Add a **Text** action and paste:")
                    Text("zonealert://health?steps=[Steps]&restingHR=[RestingHR]&activeCalories=[Active]")
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
                    step("6", "Replace each **[Steps]/[RestingHR]/[Active]** with its matching variable (tap to insert it).")
                    step("7", "Add **Open URLs** with that Text as input. **Run** the shortcut once to import today.")
                    step("8", "Optional: in the **Automation** tab, run it daily (e.g. 7am) so it imports hands-free.")
                    Text("Tip: numbers like 8412.0 are fine — the app rounds them. Sleep is harder to total in Shortcuts, so it's optional; leave it out and it shows “—”.")
                        .font(.caption2).foregroundColor(.secondary)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
            }

            Text("Why a Shortcut? A free sideloaded build can't read Apple Health directly, but the Shortcuts app can — so it reads the data and hands it to Zone Alert through a link. No internet, no account.")
                .font(.caption2).foregroundColor(.secondary)
        }
    }

    private func step(_ n: String, _ md: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(n).font(.caption.bold()).foregroundColor(.pink)
                .frame(width: 16, alignment: .leading)
            Text(.init(md)).font(.caption).foregroundColor(.secondary)
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
