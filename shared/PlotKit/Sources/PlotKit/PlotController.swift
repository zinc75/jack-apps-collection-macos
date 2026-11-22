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
        gap
        ToolbarItem(placement: .primaryAction) {
            Button { controller.showsHelp.toggle() } label: { Label(labels.gesturesTitle, systemImage: "info.circle") }
                .help(labels.gesturesTitle)
                .popover(isPresented: Binding(get: { controller.showsHelp }, set: { controller.showsHelp = $0 }), arrowEdge: .bottom) {
                    PlotGesturesHelp(title: labels.gesturesTitle, sections: labels.gestures)
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
