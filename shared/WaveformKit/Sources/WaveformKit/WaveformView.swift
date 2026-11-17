// SPDX-License-Identifier: MIT

import SwiftUI

/// Where a point of the waveform falls in the file.
public enum WaveformGeometry {
    /// The position in the file, from 0 to 1, of a point `x` points from the left edge of a view `width` points wide.
    public static func fraction(x: Double, width: Double) -> Double {
        guard width > 0 else { return 0 }
        return min(max(x / width, 0), 1)
    }
}

/// The waveform of a file: one lane per channel, all at the same scale (1.0 is full scale and fills half a lane), so
/// that the levels of the channels can be compared. What has been played is drawn in `playedColor`, the rest in
/// `unplayedColor`, with a line at the position. A click or a drag asks to move there.
///
/// The view knows nothing about playing: give it the position, from whatever drives the playback. The bars are not
/// drawn again when only the position changes.
public struct WaveformView: View {
    let peaks: WaveformPeaks?
    let channels: Int
    let position: Double
    let laneHeight: CGFloat
    let playedColor: Color
    let unplayedColor: Color
    let clipColor: Color
    let accessibilityLabel: LocalizedStringKey
    let onSeek: ((Double) -> Void)?
    let channelRange: Range<Int>?

    /// - Parameters:
    ///   - peaks: the peaks, which can be incomplete while the file is being read; nil shows empty lanes.
    ///   - channels: lanes to show while there are no peaks yet.
    ///   - position: from 0 to 1.
    ///   - playedColor: take it from the accent of the application, not from the system one.
    ///   - onSeek: called with the position asked, from 0 to 1.
    ///   - channelRange: show only these channels (a column of a file with many channels); nil shows them all.
    public init(peaks: WaveformPeaks?, channels: Int = 2, position: Double, laneHeight: CGFloat = 60,
                playedColor: Color, unplayedColor: Color = .secondary.opacity(0.55), clipColor: Color = .red,
                accessibilityLabel: LocalizedStringKey = "Waveform", onSeek: ((Double) -> Void)? = nil,
                channelRange: Range<Int>? = nil) {
        self.channelRange = channelRange
        self.peaks = peaks
        self.channels = channels
        self.position = position
        self.laneHeight = laneHeight
        self.playedColor = playedColor
        self.unplayedColor = unplayedColor
        self.clipColor = clipColor
        self.accessibilityLabel = accessibilityLabel
        self.onSeek = onSeek
    }

    private var firstLane: Int { channelRange?.lowerBound ?? 0 }
    private var laneCount: Int { channelRange?.count ?? max(peaks?.channels ?? channels, 1) }
    public var height: CGFloat { CGFloat(laneCount) * laneHeight }

    public var body: some View {
        let fraction = min(max(position, 0), 1)
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                BarsLayer(peaks: peaks, firstLane: firstLane, laneCount: laneCount, laneHeight: laneHeight, color: unplayedColor, clipColor: clipColor, grid: true)
                    .equatable()
                BarsLayer(peaks: peaks, firstLane: firstLane, laneCount: laneCount, laneHeight: laneHeight, color: playedColor, clipColor: clipColor, grid: false)
                    .equatable()
                    .mask(alignment: .leading) { Rectangle().frame(width: width * fraction) }
                Rectangle()
                    .fill(.primary)
                    .frame(width: 2)
                    .offset(x: width * fraction - 1)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                onSeek?(WaveformGeometry.fraction(x: value.location.x, width: width))
            })
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(Text("\(Int((fraction * 100).rounded())) %"))
        .accessibilityAdjustableAction { direction in
            let step = 0.05
            switch direction {
            case .increment: onSeek?(min(fraction + step, 1))
            case .decrement: onSeek?(max(fraction - step, 0))
            @unknown default: break
            }
        }
    }
}

/// The bars of every lane in one colour. Equatable on what changes the drawing, so that SwiftUI leaves it alone while
/// only the position of the playback moves.
private struct BarsLayer: View, Equatable {
    let peaks: WaveformPeaks?
    /// The channel drawn in the first lane (a column that starts at channel 33 has 32).
    let firstLane: Int
    let laneCount: Int
    let laneHeight: CGFloat
    let color: Color
    let clipColor: Color
    let grid: Bool

    static func == (a: BarsLayer, b: BarsLayer) -> Bool {
        a.peaks?.filledFrames == b.peaks?.filledFrames && a.peaks?.readColumnCount == b.peaks?.readColumnCount
            && a.peaks?.totalFrames == b.peaks?.totalFrames
            && a.peaks?.channels == b.peaks?.channels && a.peaks?.columns == b.peaks?.columns
            && a.firstLane == b.firstLane && a.laneCount == b.laneCount && a.laneHeight == b.laneHeight
            && a.color == b.color && a.clipColor == b.clipColor && a.grid == b.grid
    }

    /// Bars are 2 points wide, every 3 points.
    private static let barWidth: CGFloat = 2, pitch: CGFloat = 3

    var body: some View {
        Canvas { context, size in
            let count = max(Int(size.width / Self.pitch), 1)
            for lane in 0..<laneCount {
                let top = CGFloat(lane) * laneHeight, mid = top + laneHeight / 2, half = laneHeight / 2 - 2
                if grid {
                    context.fill(Path(CGRect(x: 0, y: mid - 0.25, width: size.width, height: 0.5)), with: .color(.secondary.opacity(0.25)))
                    context.fill(Path(CGRect(x: 0, y: top + laneHeight - 0.25, width: size.width, height: 0.5)), with: .color(.secondary.opacity(0.18)))
                }
                guard let peaks, firstLane + lane < peaks.channels else { continue }
                let bars = peaks.bars(channel: firstLane + lane, count: count)
                for i in 0..<count where bars.read[i] {
                    let lo = bars.minimums[i], hi = bars.maximums[i]
                    let y0 = mid - CGFloat(min(hi, 1)) * half, y1 = mid - CGFloat(max(lo, -1)) * half
                    let rect = CGRect(x: CGFloat(i) * Self.pitch, y: y0, width: Self.barWidth, height: max(y1 - y0, 1))
                    context.fill(Path(rect), with: .color(color))
                    if hi > 1 || lo < -1 {
                        // Beyond full scale: the bar stops at the edge of its lane, with a mark there.
                        let edge = hi > 1 ? top + 1 : top + laneHeight - 3
                        context.fill(Path(CGRect(x: rect.minX, y: edge, width: Self.barWidth, height: 2)), with: .color(clipColor))
                    }
                }
            }
        }
        .frame(height: CGFloat(laneCount) * laneHeight)
        .accessibilityHidden(true)
    }
}
