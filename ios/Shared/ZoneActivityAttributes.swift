import ActivityKit
import Foundation

/// Shared between the app and the widget extension. Describes the live workout
/// state shown on the Lock Screen and in the Dynamic Island.
struct ZoneActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var bpm: Int
        var zone: Int        // 0 = below Z1, 1...5
        var floor: Int
        var ceiling: Int
        var status: String   // "in", "low", "high"
    }
    var title: String
}
