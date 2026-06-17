import SwiftUI

// MARK: - Metric cell (Distance / Calories / Pace / Heart rate / Duration)

struct MetricCell: View {
    let icon: String
    let title: String
    let value: String
    let unit: String
    var valueColor: Color = .white

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.subheadline)
            .foregroundColor(Color(red: 1.0, green: 0.30, blue: 0.30))

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 38, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(valueColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(unit)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Live HR zone graph (colored bands + real-time HR line)

struct ZoneGraphView: View {
    let history: [Int]
    let mhr: Int
    let bpm: Int?

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack(alignment: .topLeading) {
                // Colored bands, Zone 5 (top) down to Zone 1 (bottom)
                VStack(spacing: 0) {
                    ForEach(Array((1...5).reversed()), id: \.self) { z in
                        ZStack(alignment: .leading) {
                            Zones.all[z - 1].color.opacity(0.85)
                            Text("\(z)")
                                .font(.caption.bold())
                                .foregroundColor(.white)
                                .padding(.leading, 6)
                        }
                    }
                }
                // Live HR line
                hrPath(width: w, height: h)
                    .stroke(Color.red, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                // Current BPM marker
                if let b = bpm {
                    let y = yFor(b, h)
                    HStack(spacing: 4) {
                        Text("\(b)").font(.caption.bold()).foregroundColor(.white)
                        Image(systemName: "heart.fill").font(.caption2).foregroundColor(.red)
                    }
                    .position(x: w - 26, y: max(10, min(h - 10, y - 12)))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func yFor(_ bpm: Int, _ h: CGFloat) -> CGFloat {
        let lo = Double(mhr) * 0.50      // bottom of Zone 1
        let hi = Double(mhr) * 1.00      // top of Zone 5
        let frac = (Double(bpm) - lo) / (hi - lo)
        let clamped = min(max(frac, 0), 1)
        return h - CGFloat(clamped) * h
    }

    private func hrPath(width w: CGFloat, height h: CGFloat) -> Path {
        Path { p in
            let pts = Array(history.suffix(150))
            guard pts.count > 1 else { return }
            let count = pts.count
            for (i, bpm) in pts.enumerated() {
                let x = w * CGFloat(i) / CGFloat(count - 1)
                let y = yFor(bpm, h)
                if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                else { p.addLine(to: CGPoint(x: x, y: y)) }
            }
        }
    }
}

// MARK: - Time in zone bars

struct TimeInZoneView: View {
    let timeInZone: [Double]   // index 1...5 used
    let currentZone: Int

    private var maxValue: Double {
        max(timeInZone[1...5].max() ?? 1, 1)
    }

    var body: some View {
        VStack(spacing: 6) {
            ForEach(Array((1...5).reversed()), id: \.self) { z in
                HStack(spacing: 8) {
                    Text("\(z)")
                        .font(.callout.bold())
                        .frame(width: 16)
                        .foregroundColor(.white)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4).fill(Zones.all[z - 1].color.opacity(0.22))
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Zones.all[z - 1].color)
                                .frame(width: max(2, g.size.width * CGFloat(timeInZone[z] / maxValue)))
                            Text(WorkoutViewModel.clock(timeInZone[z]))
                                .font(.caption.monospacedDigit())
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .padding(.trailing, 8)
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.white, lineWidth: currentZone == z ? 2 : 0)
                        )
                    }
                }
                .frame(height: 34)
            }
        }
    }
}
