import SwiftUI

/// A single heart-rate training zone, expressed as a fraction of Max HR.
struct Zone: Identifiable {
    let id: Int          // 1...5
    let name: String
    let low: Double      // lower bound as fraction of MHR
    let high: Double     // upper bound as fraction of MHR
    let color: Color
}

enum Zones {
    static let all: [Zone] = [
        Zone(id: 1, name: "Recovery", low: 0.50, high: 0.60, color: Color(red: 0.95, green: 0.80, blue: 0.25)),
        Zone(id: 2, name: "Aerobic",  low: 0.60, high: 0.70, color: Color(red: 0.30, green: 0.78, blue: 0.45)),
        Zone(id: 3, name: "Moderate", low: 0.70, high: 0.80, color: Color(red: 0.62, green: 0.42, blue: 0.94)),
        Zone(id: 4, name: "Hard",     low: 0.80, high: 0.90, color: Color(red: 0.98, green: 0.52, blue: 0.29)),
        Zone(id: 5, name: "Maximal",  low: 0.90, high: 1.00, color: Color(red: 0.98, green: 0.25, blue: 0.27)),
    ]

    /// Estimated max heart rate via the "220 − age" method.
    static func mhr(age: Int) -> Int { max(1, 220 - age) }

    /// Returns the zone number (1...5) for a given bpm, or 0 if below Zone 1.
    static func zone(forBpm bpm: Int, mhr: Int) -> Int {
        let m = Double(mhr)
        if bpm < Int(m * all[0].low) { return 0 }
        for z in all where bpm < Int(m * z.high) { return z.id }
        return 5
    }

    static func meta(_ n: Int) -> (name: String, color: Color) {
        if n == 0 { return ("Below Zone 1", Color(white: 0.55)) }
        let z = all[n - 1]
        return (z.name, z.color)
    }

    /// Lower bpm bound for a given zone number at a given MHR.
    static func lowerBpm(zone n: Int, mhr: Int) -> Int {
        guard n >= 1, n <= 5 else { return 0 }
        return Int(Double(mhr) * all[n - 1].low)
    }
    static func upperBpm(zone n: Int, mhr: Int) -> Int {
        guard n >= 1, n <= 5 else { return mhr }
        return Int(Double(mhr) * all[n - 1].high)
    }

    /// Heart-Rate Reserve (Karvonen) bounds: rest + intensity% × (mhr − rest).
    /// These shift as resting HR changes day to day, without altering max HR.
    static func lowerBpmHRR(zone n: Int, mhr: Int, rest: Int) -> Int {
        guard n >= 1, n <= 5, mhr > rest else { return lowerBpm(zone: n, mhr: mhr) }
        return rest + Int(Double(mhr - rest) * all[n - 1].low)
    }
    static func upperBpmHRR(zone n: Int, mhr: Int, rest: Int) -> Int {
        guard n >= 1, n <= 5, mhr > rest else { return upperBpm(zone: n, mhr: mhr) }
        return rest + Int(Double(mhr - rest) * all[n - 1].high)
    }
}
