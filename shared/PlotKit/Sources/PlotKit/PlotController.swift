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
    /// The page of the inspector that is open (the identifier of a page); the first one that exists when it is not one.
    public var inspectorTab: String?
    /// The sections of the inspector that are folded (by identifier): they stay so from one page to another.
    public var foldedSections: Set<String> = []
    /// The plot shows a phase: the inspector then offers to unwrap it.
    public var hasPhase = false
    /// The plot shows magnitudes: the inspector then offers to smooth them.
    public var hasMagnitude = false
    /// The plot draws curves (a spectrum): without a gradient they have no fill at all, where a signal in time has a flat one. The inspector
    /// says "None" instead of "Flat" then.
    public var fillCanBeNone = false
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
    var includesInspectorControls: Bool
    var placement: ToolbarItemPlacement
    var centered: Bool
    var reservedInspectorWidth: CGFloat

    /// - Parameters:
    ///   - placement: where the tools go in the toolbar: at the trailing edge by default, or `.navigation` to keep them at the leading edge, away from an
    ///     inspector that is open.
    ///   - centered: all the tools in one item in the middle of the toolbar (`.principal`), between the title and the controls of the inspector,
    ///     instead of groups at the trailing edge that an inspector that is open cuts across.
    ///   - reservedInspectorWidth: the width of the inspector of the window, which must be fixed: the toolbar keeps that much room at its right (less
    ///     the two controls of the inspector), so that the tools stay over the plot. The system lays a toolbar out once and does not do it again when an
    ///     item changes its width, so the room is the same whether the inspector is shown or not.
    ///   - includesInspectorControls: whether the help of the gestures and the button of the inspector are in this toolbar. A window
    ///   that wants them over its inspector, at the far right, leaves them out and puts `PlotInspectorToolbarContent` there.
    public init(controller: PlotController, labels: PlotLabels = PlotLabels(), accent: Color = .accentColor, includesInspectorControls: Bool = true,
                placement: ToolbarItemPlacement = .primaryAction, centered: Bool = false, reservedInspectorWidth: CGFloat = 0) {
        self.controller = controller
        self.labels = labels
        self.accent = accent
        self.includesInspectorControls = includesInspectorControls
        self.placement = placement
        self.centered = centered
        self.reservedInspectorWidth = reservedInspectorWidth
    }

    /// A gap between two groups: from macOS 26 the system draws one glass shape around neighbouring buttons, and the gap is what
    /// makes one shape per category.
    @ToolbarContentBuilder private var gap: some ToolbarContent {
        if #available(macOS 26.0, *) { ToolbarSpacer(.fixed, placement: placement) }
    }

    public var body: some ToolbarContent {
        centeredPart
        channelsPart
        toolsPart
        scalesPart
        trailingPart
    }

    /// Everything in one item, in the middle of the toolbar.
    @ToolbarContentBuilder private var centeredPart: some ToolbarContent {
        if centered {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    HStack(spacing: 2) {
                        centeredMode(.zoomBox, "rectangle.dashed", labels.zoomBox)
                        centeredMode(.pan, "hand.draw", labels.pan)
                        centeredMode(.measure, "ruler", labels.measure)
                    }
                    separator
                    HStack(spacing: 2) { zoomButtons }
                    separator
                    HStack(spacing: 2) { fitButtons }
                    if !controller.scaleSupport.isEmpty {
                        separator
                        HStack(spacing: 2) { scaleMenus }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }

    private var separator: some View { Divider().frame(height: 18) }

    /// The icon of a button of the centered toolbar: a fixed size, so that the buttons are as easy to hit as those of the other toolbars.
    private func icon(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 15)).frame(width: 30, height: 26).contentShape(Rectangle())
    }

    private func iconButton(_ symbol: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { icon(symbol) }.buttonStyle(.borderless).help(help)
    }

    /// A mode of the drag: the one that is on has the accent.
    private func centeredMode(_ mode: PlotMode, _ symbol: String, _ help: String) -> some View {
        let on = controller.mode == mode
        return Button { controller.mode = mode } label: {
            icon(symbol)
                .foregroundStyle(on ? Color.white : Color.primary)
                .background(on ? accent : Color.clear, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    @ViewBuilder private var zoomButtons: some View {
        iconButton("plus.magnifyingglass", labels.zoomIn + " (" + labels.zoomModifiers + ")") { controller.zoomIn() }
        iconButton("minus.magnifyingglass", labels.zoomOut + " (" + labels.zoomModifiers + ")") { controller.zoomOut() }
    }

    @ViewBuilder private var fitButtons: some View {
        iconButton("arrow.up.and.down", labels.autoscale) { controller.autoscaleVertical() }
        iconButton("arrow.up.left.and.down.right.magnifyingglass", labels.reset) { controller.showEverything() }
    }

    @ViewBuilder private var scaleMenus: some View {
        if controller.scaleSupport.contains(.x) {
            Menu {
                Picker(labels.xAxis, selection: Binding(get: { controller.xScale }, set: { controller.xScale = $0 })) {
                    Text(labels.linear).tag(AxisScale.linear)
                    Text(labels.logarithmic).tag(AxisScale.logarithmic)
                }
                .pickerStyle(.inline)
            } label: { Image(systemName: "arrow.left.and.right").font(.system(size: 15)) }
            .menuStyle(.borderlessButton).fixedSize().help(labels.xAxis)
        }
        if controller.scaleSupport.contains(.y) {
            Menu {
                Picker(labels.yAxis, selection: Binding(get: { controller.yScale }, set: { controller.yScale = $0 })) {
                    Text(labels.linear).tag(AmplitudeScale.linear)
                    Text(labels.decibels).tag(AmplitudeScale.decibels(floor: controller.decibelFloor))
                }
                .pickerStyle(.inline)
            } label: { Image(systemName: "arrow.up.and.down").font(.system(size: 15)) }
            .menuStyle(.borderlessButton).fixedSize().help(labels.yAxis)
        }
    }

    @ToolbarContentBuilder private var channelsPart: some ToolbarContent {
        if !centered, let series = controller.series, series.items.count > 1, !controller.hasInspector {
            ToolbarItem(placement: placement) {
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
        if !centered { toolGroups }
    }

    @ToolbarContentBuilder private var toolGroups: some ToolbarContent {
        ToolbarItemGroup(placement: placement) {
            modeButton(.zoomBox, "rectangle.dashed", labels.zoomBox)
            modeButton(.pan, "hand.draw", labels.pan)
            modeButton(.measure, "ruler", labels.measure)
        }
        gap
        ToolbarItemGroup(placement: placement) {
            Button { controller.zoomIn() } label: { Label(labels.zoomIn, systemImage: "plus.magnifyingglass") }
                .help(labels.zoomIn + " (" + labels.zoomModifiers + ")")
            Button { controller.zoomOut() } label: { Label(labels.zoomOut, systemImage: "minus.magnifyingglass") }
                .help(labels.zoomOut + " (" + labels.zoomModifiers + ")")
        }
        gap
        ToolbarItemGroup(placement: placement) {
            Button { controller.autoscaleVertical() } label: { Label(labels.autoscale, systemImage: "arrow.up.and.down") }
                .help(labels.autoscale)
            Button { controller.showEverything() } label: { Label(labels.reset, systemImage: "arrow.up.left.and.down.right.magnifyingglass") }
                .help(labels.reset)
        }
    }

    @ToolbarContentBuilder private var scalesPart: some ToolbarContent {
        if !centered { scaleGroup }
    }

    @ToolbarContentBuilder private var scaleGroup: some ToolbarContent {
        gap
        ToolbarItemGroup(placement: placement) {
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
        if includesInspectorControls { PlotInspectorToolbarContent(controller: controller, labels: labels, reservedWidth: reservedInspectorWidth) }
    }

    private func modeButton(_ mode: PlotMode, _ symbol: String, _ help: String) -> some View {
        Toggle(isOn: Binding(get: { controller.mode == mode }, set: { if $0 { controller.mode = mode } })) {
            Label(help, systemImage: symbol)
        }
        .toggleStyle(.button).tint(accent).help(help)
    }
}

/// The help of the gestures and the button that shows the inspector: what goes at the far right of the toolbar, over the inspector when it
/// is open, while the tools of `PlotToolbarContent` stay over the plot.
public struct PlotInspectorToolbarContent: ToolbarContent {
    let controller: PlotController
    var labels: PlotLabels
    var reservedWidth: CGFloat

    public init(controller: PlotController, labels: PlotLabels = PlotLabels(), reservedWidth: CGFloat = 0) {
        self.controller = controller
        self.labels = labels
        self.reservedWidth = reservedWidth
    }

    @ToolbarContentBuilder private var gap: some ToolbarContent {
        if #available(macOS 26.0, *) { ToolbarSpacer(.fixed, placement: .primaryAction) }
    }

    /// The room under the inspector that the tools must not take: its width less what the two controls need. The system does not split a
    /// toolbar in two at the edge of an inspector, so the room is made by an invisible item.
    @ToolbarContentBuilder private var room: some ToolbarContent {
        let width = reservedWidth - Self.controlsWidth
        if width > 1 {
            if #available(macOS 26.0, *) {
                ToolbarItem(placement: .primaryAction) { Color.clear.frame(width: width, height: 1).accessibilityHidden(true) }
                    .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .primaryAction) { Color.clear.frame(width: width, height: 1).accessibilityHidden(true) }
            }
        }
    }

    /// What the help and the button of the inspector take in the toolbar, with the gaps and the margin at the right: found by trying.
    static let controlsWidth: CGFloat = 110

    public var body: some ToolbarContent {
        room
        gap
        ToolbarItem(placement: .primaryAction) {
            Button { controller.showsHelp.toggle() } label: { Label(labels.gesturesTitle, systemImage: "questionmark.circle") }
                .help(labels.gesturesTitle)
                .popover(isPresented: Binding(get: { controller.showsHelp }, set: { controller.showsHelp = $0 }), arrowEdge: .bottom) {
                    PlotGesturesHelp(title: labels.gesturesTitle, sections: labels.gestures)
                }
        }
        if controller.hasInspector {
            // The button of the inspector goes to the right of its area, the help stays at the left.
            if #available(macOS 26.0, *) { ToolbarSpacer(.flexible, placement: .primaryAction) } else { gap }
            ToolbarItem(placement: .primaryAction) {
                Button { controller.showsInspector.toggle() } label: { Label(labels.inspector, systemImage: "sidebar.trailing") }
                    .help(labels.inspector)
            }
        }
    }
}
