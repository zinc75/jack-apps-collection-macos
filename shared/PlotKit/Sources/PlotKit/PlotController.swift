// SPDX-License-Identifier: MIT

import Observation
import SwiftUI

/// The state a plot shares with the toolbar of the window around it: the mode of the drag, and the commands. A window that has a
/// toolbar of its own gives the plot a controller and puts `PlotToolbarContent` in it, so that the plot has the same buttons as
/// the other tools of the window instead of a bar of its own.
@MainActor
@Observable
public final class PlotController {
    /// What a drag in the plot area does.
    public var mode: PlotMode = .zoomBox
    /// Whether the help of the gestures is shown.
    public var showsHelp = false
    /// The channels of the file, if the plot has several: the toolbar then has one button that opens the list of them.
    public var series: PlotSeriesSet?
    /// Whether the list of the channels is shown in a popover (the window has no inspector).
    public var showsChannels = false
    /// The window has an inspector bound to `showsInspector`, with `PlotInspector` in it: one button of the toolbar shows and hides it,
    /// and the channels are in it, not in a popover over the plot.
    public var hasInspector = false
    public var showsInspector = false
    /// The plot shows a phase: the inspector then offers to unwrap it.
    public var hasPhase = false
    /// The delay of each phase curve, which "Remove delay" takes out: the plot says it, the inspector shows it.
    public struct PhaseDelay: Equatable, Sendable {
        public var name: String
        public var seconds: Double
        /// Fitted to the phase, rather than given with the curve.
        public var isEstimated: Bool
    }
    public var phaseDelays: [PhaseDelay] = []
    /// How the plot looks: what the inspector sets, what the plots follow.
    public let display = PlotDisplayOptions()

    /// The scales a plot lets the person switch, in the toolbar: the plot says which, and the others are not shown.
    public struct ScaleSupport: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let x = ScaleSupport(rawValue: 1)
        public static let y = ScaleSupport(rawValue: 2)
    }
    public var scaleSupport: ScaleSupport = []
    /// The scale of the horizontal axis and the way the vertical one is drawn, as the toolbar sets them.
    public var xScale: AxisScale = .linear
    public var yScale: AmplitudeScale = .linear
    /// The floor of the decibel scale the toolbar offers.
    public var decibelFloor: Double = -120

    @ObservationIgnored var zoomAction: (Double) -> Void = { _ in }
    @ObservationIgnored var autoscaleAction: () -> Void = {}
    @ObservationIgnored var resetAction: () -> Void = {}

    public init() {}

    /// Zooms around the centre of the plot: on the horizontal axis, with ⌥ held on the vertical one, with ⇧ on both.
    public func zoomIn() { zoomAction(PlotGestures.buttonFactor) }
    public func zoomOut() { zoomAction(1 / PlotGestures.buttonFactor) }
    /// Fits the vertical axis to what the horizontal range shows.
    public func autoscaleVertical() { autoscaleAction() }
    /// Shows the whole signal.
    public func showEverything() { resetAction() }
}

/// The buttons of the plot for the toolbar of a window: the modes as buttons that stay pressed, then the zoom, then the
/// autoscale and the return to the whole signal. They are grouped as the other buttons of a window toolbar are.
public struct PlotToolbarContent: ToolbarContent {
    let controller: PlotController
    var labels: PlotLabels
    var accent: Color

    public init(controller: PlotController, labels: PlotLabels = PlotLabels(), accent: Color = .accentColor) {
        self.controller = controller
        self.labels = labels
        self.accent = accent
    }

    /// A gap between two groups: from macOS 26 the system draws one glass shape around neighbouring buttons, and the gap is what
    /// makes one shape per category.
    @ToolbarContentBuilder private var gap: some ToolbarContent {
        if #available(macOS 26.0, *) { ToolbarSpacer(.fixed, placement: .primaryAction) }
    }

    public var body: some ToolbarContent {
        channelsPart
        toolsPart
        scalesPart
        trailingPart
    }

    @ToolbarContentBuilder private var channelsPart: some ToolbarContent {
        if let series = controller.series, series.items.count > 1, !controller.hasInspector {
            ToolbarItem(placement: .primaryAction) {
                Button { controller.showsChannels.toggle() } label: {
                    Label("\(labels.channels) \(series.visible.count)/\(series.items.count)", systemImage: "waveform.path.ecg")
                }
                .labelStyle(.titleAndIcon)
                .help(labels.channels)
                .popover(isPresented: Binding(get: { controller.showsChannels }, set: { controller.showsChannels = $0 }), arrowEdge: .bottom) {
                    PlotChannelList(series: series, labels: labels)
                }
            }
            gap
        }
    }

    @ToolbarContentBuilder private var toolsPart: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            modeButton(.zoomBox, "rectangle.dashed", labels.zoomBox)
            modeButton(.pan, "hand.draw", labels.pan)
            modeButton(.measure, "ruler", labels.measure)
        }
        gap
        ToolbarItemGroup(placement: .primaryAction) {
            Button { controller.zoomIn() } label: { Label(labels.zoomIn, systemImage: "plus.magnifyingglass") }
                .help(labels.zoomIn + " (" + labels.zoomModifiers + ")")
            Button { controller.zoomOut() } label: { Label(labels.zoomOut, systemImage: "minus.magnifyingglass") }
                .help(labels.zoomOut + " (" + labels.zoomModifiers + ")")
        }
        gap
        ToolbarItemGroup(placement: .primaryAction) {
            Button { controller.autoscaleVertical() } label: { Label(labels.autoscale, systemImage: "arrow.up.and.down") }
                .help(labels.autoscale)
            Button { controller.showEverything() } label: { Label(labels.reset, systemImage: "arrow.counterclockwise") }
                .help(labels.reset)
        }
    }

    @ToolbarContentBuilder private var scalesPart: some ToolbarContent {
        gap
        ToolbarItemGroup(placement: .primaryAction) {
            if controller.scaleSupport.contains(.x) {
                Menu {
                    Picker(labels.xAxis, selection: Binding(get: { controller.xScale }, set: { controller.xScale = $0 })) {
                        Text(labels.linear).tag(AxisScale.linear)
                        Text(labels.logarithmic).tag(AxisScale.logarithmic)
                    }
                    .pickerStyle(.inline)
                } label: { Label(labels.xAxis, systemImage: "arrow.left.and.right") }
                .help(labels.xAxis)
            }
            if controller.scaleSupport.contains(.y) {
                Menu {
                    Picker(labels.yAxis, selection: Binding(get: { controller.yScale }, set: { controller.yScale = $0 })) {
                        Text(labels.linear).tag(AmplitudeScale.linear)
                        Text(labels.decibels).tag(AmplitudeScale.decibels(floor: controller.decibelFloor))
                    }
                    .pickerStyle(.inline)
                } label: { Label(labels.yAxis, systemImage: "arrow.up.and.down") }
                .help(labels.yAxis)
            }
        }
    }

    @ToolbarContentBuilder private var trailingPart: some ToolbarContent {
        gap
        ToolbarItem(placement: .primaryAction) {
            Button { controller.showsHelp.toggle() } label: { Label(labels.gesturesTitle, systemImage: "info.circle") }
                .help(labels.gesturesTitle)
                .popover(isPresented: Binding(get: { controller.showsHelp }, set: { controller.showsHelp = $0 }), arrowEdge: .bottom) {
                    PlotGesturesHelp(title: labels.gesturesTitle, sections: labels.gestures)
                }
        }
        if controller.hasInspector {
            gap
            ToolbarItem(placement: .primaryAction) {
                Button { controller.showsInspector.toggle() } label: { Label(labels.inspector, systemImage: "sidebar.trailing") }
                    .help(labels.inspector)
            }
        }
    }

    private func modeButton(_ mode: PlotMode, _ symbol: String, _ help: String) -> some View {
        Toggle(isOn: Binding(get: { controller.mode == mode }, set: { if $0 { controller.mode = mode } })) {
            Label(help, systemImage: symbol)
        }
        .toggleStyle(.button).tint(accent).help(help)
    }
}
