// SPDX-License-Identifier: MIT

import SwiftUI

/// How a time is written: `m:ss`, `h:mm:ss`, and with tenths when asked. Times are cut, not rounded, so that a
/// clock never shows a second before it has come.
public enum TimeFormat {
    public static func clock(_ seconds: Double, tenths: Bool = false) -> String {
        // A tiny margin, so that 0.6 computed as 0.5999999999 still reads 0.6.
        let s = max(seconds.isFinite ? seconds : 0, 0) + 1e-9
        let whole = Int(s.rounded(.down))
        let h = whole / 3600, m = whole % 3600 / 60, sec = whole % 60
        let head = h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
        guard tenths else { return head }
        let tenth = Int(((s - Double(whole)) * 10).rounded(.down))
        return head + "." + String(min(tenth, 9))
    }
}

/// One graduation of the ruler.
public struct RulerTick: Equatable, Sendable {
    /// Seconds from the start of the file.
    public let time: Double
    /// Where it falls along the file, from 0 to 1.
    public let fraction: Double
    public let label: String
}

/// Which graduations to draw above a waveform: a round step (1, 2, 5, 10, 15, 30 seconds, 1, 2, 5, 10 minutes …)
/// chosen so that two labels are never closer than `minSpacing` points.
public enum TimeRuler {
    static let steps: [Double] = [0.1, 0.2, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 900, 1800, 3600, 7200, 14400, 28800]

    public static func step(duration: Double, width: Double, minSpacing: Double = 64) -> Double? {
        guard duration > 0, width > 0 else { return nil }
        let needed = duration * minSpacing / width
        return steps.first { $0 >= needed } ?? steps.last
    }

    public static func ticks(duration: Double, width: Double, minSpacing: Double = 64) -> [RulerTick] {
        guard let step = step(duration: duration, width: width, minSpacing: minSpacing) else { return [] }
        let count = Int((duration / step).rounded(.down))
        return (0...count).map { k in
            let t = Double(k) * step
            return RulerTick(time: t, fraction: t / duration, label: TimeFormat.clock(t, tenths: step < 1))
        }
    }
}

/// The ruler itself: the graduations and their labels, over the width it is given. Put it above a `WaveformView`
/// of the same width.
public struct TimeRulerView: View {
    let duration: Double
    public init(duration: Double) { self.duration = duration }

    public static let height: CGFloat = 18

    public var body: some View {
        Canvas { context, size in
            let ticks = TimeRuler.ticks(duration: duration, width: size.width)
            for tick in ticks {
                let x = tick.fraction * size.width
                context.fill(Path(CGRect(x: x - 0.5, y: size.height - 4, width: 1, height: 4)), with: .color(.secondary.opacity(0.6)))
                // The first label starts at the left edge, the last ends at the right edge, the others are centred.
                let anchor: UnitPoint = tick.fraction <= 0 ? .topLeading : (size.width - x < 22 ? .topTrailing : .top)
                context.draw(Text(verbatim: tick.label).font(.system(size: 10).monospacedDigit()).foregroundStyle(.secondary),
                             at: CGPoint(x: x, y: 0), anchor: anchor)
            }
        }
        .frame(height: Self.height)
        .accessibilityHidden(true)
    }
}
