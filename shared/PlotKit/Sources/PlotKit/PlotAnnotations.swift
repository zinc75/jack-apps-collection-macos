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
        }
    }
}

extension PlotDrawing {
    /// The names of the marks and of the region, over everything else. They are placed together so that they never overlap: each one goes beside
    /// its line, on the side that has room, and when two would touch it goes down one row, so a short range in a long signal, where the lines are a
    /// few pixels apart, still reads. A name that finds no place is left out.
    func drawNames(_ ctx: inout GraphicsContext, _ t: PlotTransform, _ plot: CGRect, _ palette: PlotPalette) {
        struct Name {
            var text: GraphicsContext.ResolvedText
            var width: CGFloat
            /// Where it may go, in order of preference: the x of its edge and the side of the text that sits on it.
            var places: [(x: CGFloat, anchor: UnitPoint)]
            /// The lines that belong to it, which it may sit against.
            var own: [CGFloat]
        }
        func resolve(_ name: String, _ color: Color) -> (GraphicsContext.ResolvedText, CGFloat) {
            let text = ctx.resolve(Text(verbatim: name).font(.system(size: 10, weight: .semibold)).foregroundColor(color))
            return (text, text.measure(in: CGSize(width: 240, height: 20)).width)
        }
        var lines: [CGFloat] = []
        var names: [Name] = []
        for marker in annotations.markers {
            let px = t.x(marker.x)
            guard px >= plot.minX - 1, px <= plot.maxX + 1 else { continue }
            lines.append(px)
            guard !marker.name.isEmpty else { continue }
            let (text, w) = resolve(marker.name, marker.color)
            names.append(Name(text: text, width: w, places: [(px + 4, .topLeading), (px - 4, .topTrailing)], own: [px]))
        }
        names.sort { $0.own[0] < $1.own[0] }
        if let region, !region.style.name.isEmpty {
            let lo = t.x(region.range.lowerBound), hi = t.x(region.range.upperBound)
            let (text, w) = resolve(region.style.name, region.style.color(isDark: palette.isDark))
            // Inside the range when the name fits there; otherwise just outside it, on either side.
            var places: [(x: CGFloat, anchor: UnitPoint)] = []
            if hi - lo >= w + 16 { places.append((max(lo, plot.minX) + 8, .topLeading)) }
            places.append((hi + 6, .topLeading))
            places.append((lo - 6, .topTrailing))
            if hi - lo < w + 16 { places.append((max(lo, plot.minX) + 8, .topLeading)) }
            names.append(Name(text: text, width: w, places: places, own: [lo, hi]))
            lines.append(contentsOf: [lo, hi])
        }

        let rowHeight: CGFloat = 14, top = plot.minY + 4
        let rows = max(1, min(5, Int((plot.height - 8) / rowHeight)))
        var taken: [[ClosedRange<CGFloat>]] = Array(repeating: [], count: rows)
        for name in names {
            let others = lines.filter { line in !name.own.contains { abs($0 - line) < 0.5 } }
            search: for row in 0..<rows {
                for place in name.places {
                    let x0 = place.anchor == .topLeading ? place.x : place.x - name.width
                    let span = x0...(x0 + name.width)
                    guard span.lowerBound >= plot.minX + 2, span.upperBound <= plot.maxX - 2 else { continue }
                    if taken[row].contains(where: { $0.lowerBound < span.upperBound + 6 && span.lowerBound < $0.upperBound + 6 }) { continue }
                    // Not across the line of another name.
                    if others.contains(where: { $0 > span.lowerBound - 2 && $0 < span.upperBound + 2 }) { continue }
                    ctx.draw(name.text, at: CGPoint(x: place.x, y: top + CGFloat(row) * rowHeight), anchor: place.anchor)
                    taken[row].append(span)
                    break search
                }
            }
        }
    }
}

