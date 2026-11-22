// SPDX-License-Identifier: MIT

import Observation
import SwiftUI

/// One channel of a plot as the person sees it: a name, a colour they can choose, and whether it is shown.
public struct PlotSeries: Identifiable, Equatable {
    /// The number of the channel from 0: the colour of a channel belongs to it, whatever other channels are shown.
    public let id: Int
    public var name: String
    public var color: Color
    public var isVisible: Bool

    public init(id: Int, name: String, color: Color, isVisible: Bool = true) {
        self.id = id
        self.name = name
        self.color = color
        self.isVisible = isVisible
    }
}

/// The channels of a file, with their colours and which are shown. The same set feeds the plot in time, the spectrum and the
/// phase, so that a channel has the same colour in every view and whatever other channels are shown. An application keeps the
/// colours the person chose between launches if it wants to.
@MainActor
@Observable
public final class PlotSeriesSet {
    public var items: [PlotSeries]

    /// The colours channels get by default: the accent of the application, then colours that are neither the box's nor the
    /// measure's. The same as the traces of a plot get by position.
    public static func defaultColor(_ channel: Int, accent: Color) -> Color {
        PlotPalette(accent: accent, isDark: true).trace(channel)
    }

    public init(count: Int, accent: Color = .accentColor, names: [String] = []) {
        items = (0..<max(0, count)).map { i in
            PlotSeries(id: i, name: i < names.count ? names[i] : "\(i + 1)", color: Self.defaultColor(i, accent: accent))
        }
    }

    public var visible: [PlotSeries] { items.filter(\.isVisible) }

    /// Puts a channel first: it is drawn on top of the others, where they overlap. The colours do not move with the order: they
    /// belong to the channels.
    public func bringToFront(_ id: Int) {
        guard let i = items.firstIndex(where: { $0.id == id }), i > 0 else { return }
        items.insert(items.remove(at: i), at: 0)
    }

    /// Moves channels in the list (a drag of a row): the order is the order of drawing, the first on top.
    public func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
    }

    /// Shows only this channel, or all of them again when it is the only one shown.
    public func solo(_ id: Int) {
        let onlyThis = items.allSatisfy { $0.isVisible == ($0.id == id) }
        for i in items.indices { items[i].isVisible = onlyThis ? true : items[i].id == id }
    }

    /// The traces of the visible channels, in the colour of each; `signal` gives the signal of a channel.
    public func traces(_ signal: (Int) -> PlotSignal) -> [PlotTrace] {
        visible.map { PlotTrace(name: $0.name, signal: signal($0.id), color: $0.color) }
    }

    /// The curves of the visible channels, in the colour of each; `curve` gives the data of a channel.
    public func curves(_ curve: (Int) -> (x: [Double], y: [Double]), filled: Bool = true) -> [PlotCurve] {
        let shown = visible
        return shown.map { s in
            let data = curve(s.id)
            // Whether the area under a curve has a gradient is up to the plot: the display options and the number of curves decide.
            return PlotCurve(name: s.name, x: data.x, y: data.y, color: s.color, filled: filled)
        }
    }
}

extension PlotSeriesSet {
    public func showAll() { for i in items.indices { items[i].isVisible = true } }
    public func hideAll() { for i in items.indices { items[i].isVisible = false } }
}

/// The list of the channels, one under the other: a box to show or hide each, its colour (a click chooses another), its name, and
/// a button to show it alone. It is what a click on the channels button of the toolbar opens.
public struct PlotChannelList: View {
    @Bindable var series: PlotSeriesSet
    var labels: PlotLabels
    var inInspector: Bool

    /// - Parameter inInspector: the list fills the panel of the window that shows it (an inspector), instead of having the fixed
    ///   size of a popover.
    public init(series: PlotSeriesSet, labels: PlotLabels = PlotLabels(), inInspector: Bool = false) {
        self.series = series
        self.labels = labels
        self.inInspector = inInspector
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(labels.channels).font(.headline)
                Spacer()
                Button(labels.allChannels) { series.showAll() }.disabled(series.items.allSatisfy(\.isVisible))
                Button(labels.noChannels) { series.hideAll() }.disabled(series.visible.isEmpty)
            }
            .buttonStyle(.link).font(.callout)
            Divider()
            // The rows are dragged to reorder them: the first is drawn on top.
            List {
                ForEach($series.items) { $item in
                    HStack(spacing: 8) {
                        Image(systemName: "line.3.horizontal").font(.system(size: 11)).foregroundStyle(.tertiary).help(labels.channelsHelp)
                        Toggle("", isOn: $item.isVisible).labelsHidden().toggleStyle(.checkbox).tint(item.color)
                        ColorPicker("", selection: $item.color, supportsOpacity: false).labelsHidden().frame(width: 38)
                        Text(item.name).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundStyle(item.isVisible ? .primary : .secondary)
                        Button { series.bringToFront(item.id) } label: { Image(systemName: "square.2.layers.3d.top.filled") }
                            .buttonStyle(.borderless).help(labels.toFront)
                            .disabled(series.items.first?.id == item.id)
                        Button(labels.onlyChannel) { series.solo(item.id) }.buttonStyle(.link).font(.callout)
                    }
                    .listRowSeparator(.hidden)
                    .contextMenu {
                        Button(labels.toFront) { series.bringToFront(item.id) }.disabled(series.items.first?.id == item.id)
                        Button(labels.onlyChannel) { series.solo(item.id) }
                    }
                }
                .onMove { series.move(fromOffsets: $0, toOffset: $1) }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .frame(height: min(CGFloat(series.items.count) * 34 + 10, inInspector ? 440 : 360))
            Text(labels.channelsHelp).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(inInspector ? 0 : 14)
        .frame(minWidth: inInspector ? 0 : 280, maxWidth: inInspector ? .infinity : 280, alignment: .top)
    }
}

/// The legend of a plot, as Plotly has one: a chip for each channel with its colour (a click on the colour chooses another), its
/// name, and a click on the name shows or hides it (a double click shows that one alone). It is the selector of channels.
public struct PlotLegend: View {
    @Bindable var series: PlotSeriesSet
    var title: String

    public init(series: PlotSeriesSet, title: String = "") {
        self.series = series
        self.title = title
    }

    public var body: some View {
        HStack(spacing: 8) {
            if !title.isEmpty { Text(title).font(.callout).foregroundStyle(.secondary) }
            ForEach($series.items) { $item in
                HStack(spacing: 5) {
                    ColorPicker("", selection: $item.color, supportsOpacity: false).labelsHidden().frame(width: 40)
                    Text(item.name).font(.callout.weight(.medium)).lineLimit(1)
                }
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(item.color.opacity(item.isVisible ? 0.16 : 0.0), in: Capsule())
                .overlay(Capsule().strokeBorder(item.color.opacity(item.isVisible ? 0.55 : 0.25), lineWidth: 1))
                .opacity(item.isVisible ? 1 : 0.5)
                .contentShape(Capsule())
                .onTapGesture(count: 2) { series.solo(item.id) }
                .onTapGesture { item.isVisible.toggle() }
            }
            Spacer(minLength: 0)
        }
    }
}
