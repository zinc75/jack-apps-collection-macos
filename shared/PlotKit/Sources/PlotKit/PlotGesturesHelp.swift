// SPDX-License-Identifier: MIT

import SwiftUI

/// One line of the help: a gesture and what it does.
public struct PlotGestureItem: Sendable, Equatable {
    public var gesture: String
    public var effect: String
    public init(_ gesture: String, _ effect: String) { self.gesture = gesture; self.effect = effect }
}

public struct PlotGestureSection: Sendable, Equatable {
    public var title: String
    public var items: [PlotGestureItem]
    public init(_ title: String, _ items: [PlotGestureItem]) { self.title = title; self.items = items }

    /// The gestures of the plot, in English. An application gives its own texts in `PlotLabels.gestures`.
    public static let defaults: [PlotGestureSection] = [
        PlotGestureSection("Zoom", [
            .init("Pinch", "Zoom the horizontal axis around the pointer"),
            .init("⌥ Pinch", "Zoom the vertical axis"),
            .init("⇧ Pinch", "Zoom both axes"),
            .init("Mouse wheel", "Same as a pinch (⌥ vertical, ⇧ both)"),
            .init("⌘ Scroll", "Same, with a trackpad or a Magic Mouse"),
            .init("Zoom buttons", "Same, around the centre (⌥-click vertical, ⇧-click both)"),
        ]),
        PlotGestureSection("Move", [
            .init("Scroll", "Slide the view (trackpad, Magic Mouse)"),
            .init("Drag, in Pan mode", "Slide the view"),
            .init("⇧ Drag", "Slide the view in any mode"),
        ]),
        PlotGestureSection("Box and axes", [
            .init("Drag, in Zoom mode", "Draw a box and zoom to it"),
            .init("Drag on an axis", "The middle slides it, an end changes its scale (the other end stays)"),
            .init("Double-click in the plot", "Show everything"),
            .init("Double-click on an axis", "Horizontal: show all of it. Vertical: fit to what is visible"),
        ]),
        PlotGestureSection("Measure", [
            .init("Pointer over the plot", "Crosshair with the values, at the nearest sample when they can be told apart"),
            .init("Drag, in Measure mode", "Time, frequency (1/Δt) and level between two points"),
        ]),
    ]
}

/// The help of the gestures of a plot, to show in a popover from an "i" button.
public struct PlotGesturesHelp: View {
    var title: String
    var sections: [PlotGestureSection]

    public init(title: String, sections: [PlotGestureSection]) { self.title = title; self.sections = sections }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            ForEach(sections, id: \.title) { section in
                VStack(alignment: .leading, spacing: 5) {
                    Text(section.title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 4) {
                        ForEach(section.items, id: \.gesture) { item in
                            GridRow {
                                Text(item.gesture).font(.callout.weight(.medium)).frame(width: 150, alignment: .leading)
                                Text(item.effect).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 560, alignment: .leading)
    }
}
