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
    private let spacing: CGFloat = 3   // horizontal points per sample

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let bandH = h / 5
            let contentW = max(geo.size.width, CGFloat(max(history.count, 1)) * spacing)
            HStack(spacing: 4) {
                // Fixed zone-number axis (stays put while the timeline scrolls)
                VStack(spacing: 0) {
                    ForEach(Array((1...5).reversed()), id: \.self) { z in
                        Text("\(z)")
                            .font(.caption2.bold())
                            .foregroundColor(Zones.all[z - 1].color)
                            .frame(width: 14, height: bandH)
                    }
                }
                // Scroll WITHIN here to pan the whole workout; auto-follows the live edge
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        ZStack(alignment: .topLeading) {
                            VStack(spacing: 0) {
                                ForEach(Array((1...5).reversed()), id: \.self) { z in
                                    Zones.all[z - 1].color.opacity(0.85)
                                        .frame(width: contentW, height: bandH)
                                }
                            }
                            hrPath(width: contentW, height: h)
                                .stroke(Color.red, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                            if let b = bpm, !history.isEmpty {
                                Circle().fill(Color.red).frame(width: 7, height: 7)
                                    .position(x: contentW - 3, y: yFor(b, h))
                            }
                            Color.clear.frame(width: 1, height: h)
                                .position(x: contentW - 0.5, y: h / 2).id("liveEdge")
                        }
                        .frame(width: contentW, height: h)
                    }
                    .onChange(of: history.count) { _ in proxy.scrollTo("liveEdge", anchor: .trailing) }
                    .onAppear { proxy.scrollTo("liveEdge", anchor: .trailing) }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
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
            guard history.count > 1 else { return }
            let n = history.count
            for (i, bpm) in history.enumerated() {
                let x = w * CGFloat(i) / CGFloat(n - 1)
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
