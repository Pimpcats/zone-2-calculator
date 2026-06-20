import WidgetKit
import SwiftUI
import ActivityKit

@main
struct ZoneAlertWidgetBundle: WidgetBundle {
    var body: some Widget {
        ZoneLiveActivity()
    }
}

/// The actual training-zone color (matches the in-app zone bands).
private func zoneColor(_ zone: Int) -> Color {
    switch zone {
    case 1: return Color(red: 0.95, green: 0.80, blue: 0.25)   // yellow
    case 2: return Color(red: 0.30, green: 0.78, blue: 0.45)   // green
    case 3: return Color(red: 0.62, green: 0.42, blue: 0.94)   // purple
    case 4: return Color(red: 0.98, green: 0.52, blue: 0.29)   // orange
    case 5: return Color(red: 0.98, green: 0.25, blue: 0.27)   // red
    default: return Color(white: 0.6)                          // below Zone 1
    }
}

private func statusText(_ s: String, ceiling: Int, floor: Int) -> String {
    switch s {
    case "low": return "Too low — pick it up"
    case "high": return "Too high — ease off"
    default: return "In zone (\(floor)–\(ceiling))"
    }
}

struct ZoneLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ZoneActivityAttributes.self) { context in
            // Lock Screen / banner
            HStack(spacing: 14) {
                Image(systemName: "heart.fill").foregroundColor(zoneColor(context.state.zone))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(context.state.bpm) bpm")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text(statusText(context.state.status, ceiling: context.state.ceiling, floor: context.state.floor))
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Text(context.state.zone == 0 ? "—" : "Z\(context.state.zone)")
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundColor(zoneColor(context.state.zone))
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.6))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("\(context.state.bpm)", systemImage: "heart.fill")
                        .foregroundColor(zoneColor(context.state.zone))
                        .font(.title3.bold())
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.zone == 0 ? "—" : "Zone \(context.state.zone)")
                        .font(.title3.bold())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(statusText(context.state.status, ceiling: context.state.ceiling, floor: context.state.floor))
                        .font(.caption).foregroundColor(.secondary)
                }
            } compactLeading: {
                Image(systemName: "heart.fill").foregroundColor(zoneColor(context.state.zone))
            } compactTrailing: {
                Text("\(context.state.bpm)").foregroundColor(zoneColor(context.state.zone))
            } minimal: {
                Text("\(context.state.bpm)").foregroundColor(zoneColor(context.state.zone))
            }
        }
    }
}
