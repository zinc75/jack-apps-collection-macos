// SPDX-License-Identifier: MIT

import SwiftUI

/// One horizontal bar per channel with the peak it holds and a mark when it clipped, and a scale under it. From
/// 17 channels the bars go in two columns, and they get thinner as channels are added.
public struct MeterBars: View {
    let meters: [ChannelMeter]
    let channels: Int
    let scale: any MeterScale
    let label: LocalizedStringKey
    let scaleMarks: [Double]

    /// `scale` places the levels, and the `scaleMarks` (dBFS) under the bars; `label` is read by VoiceOver.
    public init(meters: [ChannelMeter], channels: Int, scale: any MeterScale, label: LocalizedStringKey,
                scaleMarks: [Double] = [-50, -40, -30, -20, -10, -3, 0]) {
        self.meters = meters
        self.channels = channels
        self.scale = scale
        self.label = label
        self.scaleMarks = scaleMarks
    }

    private static let labelWidth: CGFloat = 30

    private var count: Int { max(channels, meters.count) }
    private var columns: Int { count > 16 ? 2 : 1 }
    private var rowsPerColumn: Int { (count + columns - 1) / columns }
    /// Rows get thinner as channels are added.
    private var rowHeight: CGFloat { count <= 2 ? 34 : count <= 4 ? 28 : count <= 8 ? 22 : count <= 16 ? 17 : 15 }
    private var totalHeight: CGFloat { CGFloat(rowsPerColumn) * rowHeight + 18 }

    public var body: some View {
        let meters = self.meters   // read here, so that the view is rebuilt when they change
        Canvas { context, size in
            let gap: CGFloat = 24
            let columnWidth = (size.width - gap * CGFloat(columns - 1)) / CGFloat(columns)
            // Room is kept on the right for the last figure of the scale, centred on the end of the track.
            let trackX = Self.labelWidth, trackWidth = columnWidth - Self.labelWidth - 10
            let barHeight = min(rowHeight * 0.56, 14)
            let gradient = Gradient(stops: [
                .init(color: Color(red: 0.13, green: 0.77, blue: 0.37), location: 0),
                .init(color: Color(red: 0.13, green: 0.77, blue: 0.37), location: 0.55),
                .init(color: Color(red: 0.98, green: 0.80, blue: 0.08), location: 0.78),
                .init(color: Color(red: 0.98, green: 0.45, blue: 0.09), location: 0.9),
                .init(color: Color(red: 0.94, green: 0.27, blue: 0.27), location: 1),
            ])
            for i in 0..<count {
                let column = i / rowsPerColumn, row = i % rowsPerColumn
                let x0 = CGFloat(column) * (columnWidth + gap)
                let y = CGFloat(row) * rowHeight + (rowHeight - barHeight) / 2
                let meter = i < meters.count ? meters[i] : .silent

                context.draw(Text(verbatim: "\(i + 1)").font(.system(size: 11, weight: .semibold).monospacedDigit()).foregroundStyle(.secondary),
                             at: CGPoint(x: x0 + 12, y: y + barHeight / 2), anchor: .center)
                let track = CGRect(x: x0 + trackX, y: y, width: trackWidth, height: barHeight)
                context.fill(Path(roundedRect: track, cornerRadius: barHeight * 0.3), with: .color(.primary.opacity(0.09)))
                if meter.level > 0 {
                    let fill = CGRect(x: track.minX, y: y, width: track.width * min(meter.level, 1), height: barHeight)
                    var layer = context
                    layer.clip(to: Path(roundedRect: track, cornerRadius: barHeight * 0.3))
                    layer.fill(Path(fill), with: .linearGradient(gradient, startPoint: CGPoint(x: track.minX, y: 0), endPoint: CGPoint(x: track.maxX, y: 0)))
                }
                if meter.peak > 0 {
                    let px = track.minX + track.width * min(meter.peak, 1)
                    context.fill(Path(CGRect(x: px - 1.5, y: y - 1, width: 2, height: barHeight + 2)), with: .color(.primary.opacity(0.85)))
                }
                if meter.clipped {
                    context.fill(Path(roundedRect: CGRect(x: track.maxX + 3, y: y, width: 6, height: barHeight), cornerRadius: 2),
                                 with: .color(Color(red: 0.94, green: 0.27, blue: 0.27)))
                }
            }
            // The scale, once under each column.
            for column in 0..<columns {
                let x0 = CGFloat(column) * (columnWidth + gap)
                let y = CGFloat(rowsPerColumn) * rowHeight + 2
                for db in scaleMarks {
                    let x = x0 + trackX + trackWidth * scale.fraction(db: db)
                    context.fill(Path(CGRect(x: x - 0.25, y: y - 3, width: 0.5, height: 4)), with: .color(.secondary))
                    context.draw(Text(verbatim: db == 0 ? "0" : "\(Int(db))").font(.system(size: 9).monospacedDigit()).foregroundStyle(.secondary),
                                 at: CGPoint(x: x, y: y + 8), anchor: .center)
                }
            }
        }
        .frame(height: totalHeight)
        .accessibilityElement()
        .accessibilityLabel(Text(label))
    }
}
