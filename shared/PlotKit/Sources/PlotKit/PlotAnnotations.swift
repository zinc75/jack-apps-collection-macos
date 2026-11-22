// SPDX-License-Identifier: MIT

import SwiftUI

/// A vertical line at a place of the horizontal axis, with a name: where an attack starts, where a tail ends.
public struct PlotMarker: Identifiable, Equatable {
    public var id: String
    /// Where it is, in the units of the horizontal axis of the plot (samples for a signal).
    public var x: Double
    public var name: String
    public var color: Color

    public init(id: String? = nil, x: Double, name: String = "", color: Color) {
        self.id = id ?? name + "@\(x)"
        self.x = x
        self.name = name
        self.color = color
    }
}

/// What an application adds to a plot over the data: marks of its own, and a range that stands out from the rest.
public struct PlotAnnotations: Equatable {
    public var markers: [PlotMarker]
    /// A range of the horizontal axis that is kept as it is while what is outside it is dimmed (the part of a response that a
    /// program reads, say).
    public var highlighted: ClosedRange<Double>?

    public init(markers: [PlotMarker] = [], highlighted: ClosedRange<Double>? = nil) {
        self.markers = markers
        self.highlighted = highlighted
    }

    var isEmpty: Bool { markers.isEmpty && highlighted == nil }
}

extension PlotDrawing {
    /// The dimming and the marks, over the data and under the box and the measure.
    func drawAnnotations(_ ctx: inout GraphicsContext, _ t: PlotTransform, _ plot: CGRect, _ palette: PlotPalette) {
        if let range = annotations.highlighted {
            let dim = palette.isDark ? Color.black.opacity(0.38) : Color.black.opacity(0.12)
            let a = t.x(range.lowerBound), b = t.x(range.upperBound)
            if a > plot.minX {
                ctx.fill(Path(CGRect(x: plot.minX, y: plot.minY, width: min(a, plot.maxX) - plot.minX, height: plot.height)), with: .color(dim))
            }
            if b < plot.maxX {
                let left = max(b, plot.minX)
                ctx.fill(Path(CGRect(x: left, y: plot.minY, width: plot.maxX - left, height: plot.height)), with: .color(dim))
            }
        }
        for marker in annotations.markers {
            let px = t.x(marker.x)
            guard px >= plot.minX - 1, px <= plot.maxX + 1 else { continue }
            var line = Path(); line.move(to: CGPoint(x: px, y: plot.minY)); line.addLine(to: CGPoint(x: px, y: plot.maxY))
            ctx.stroke(line, with: .color(marker.color), lineWidth: 1.5)
            guard !marker.name.isEmpty else { continue }
            let text = ctx.resolve(Text(verbatim: marker.name).font(.system(size: 10, weight: .semibold)).foregroundColor(marker.color))
            let w = text.measure(in: CGSize(width: 200, height: 20)).width
            // The name sits on the side of the line that has room.
            let right = px + 4 + w < plot.maxX
            ctx.draw(text, at: CGPoint(x: right ? px + 4 : px - 4, y: plot.minY + 3), anchor: right ? .topLeading : .topTrailing)
        }
    }
}
