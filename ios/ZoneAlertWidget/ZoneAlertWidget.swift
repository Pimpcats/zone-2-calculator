import WidgetKit
import SwiftUI
import ActivityKit

@main
struct ZoneAlertWidgetBundle: WidgetBundle {
    var body: some Widget {
        ZoneLiveActivity()
    }
}

private func statusColor(_ s: String) -> Color {
    switch s {
    case "low": return .cyan
    case "high": return .orange
    default: return .green
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
                Image(systemName: "heart.fill").foregroundColor(statusColor(context.state.status))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(context.state.bpm) bpm")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text(statusText(context.state.status, ceiling: context.state.ceiling, floor: context.state.floor))
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Text(context.state.zone == 0 ? "—" : "Z\(context.state.zone)")
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundColor(statusColor(context.state.status))
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.6))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("\(context.state.bpm)", systemImage: "heart.fill")
                        .foregroundColor(statusColor(context.state.status))
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
                Image(systemName: "heart.fill").foregroundColor(statusColor(context.state.status))
            } compactTrailing: {
                Text("\(context.state.bpm)").foregroundColor(statusColor(context.state.status))
            } minimal: {
                Text("\(context.state.bpm)").foregroundColor(statusColor(context.state.status))
            }
        }
    }
}
