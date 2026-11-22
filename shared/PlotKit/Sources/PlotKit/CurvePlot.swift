// SPDX-License-Identifier: MIT

import SwiftUI

/// A plot of curves whose abscissas are not regular, for the frequency domain: the magnitude of a spectrum in decibels, its
/// phase, a group delay. The horizontal axis is linear or logarithmic and the vertical one linear or in decibels, switched
/// with the toolbar of the window (the `PlotController` of the window carries the scales) or by the application.
///
/// The crosshair, the measure (the ratio of two frequencies in octaves), the box zoom and the gestures are those of `SignalPlot`.
public struct CurvePlot: View {
    let curves: [PlotCurve]
    @Binding var viewport: PlotViewport
    var xUnit: String
    var yUnit: String
    var yScale: AmplitudeScale
    var accent: Color
    var labels: PlotLabels
    var controller: PlotController?
    var yScaleSwitchable: Bool
    var previewHover: CGPoint?
    var previewMeasure: PlotSegment?

    /// - Parameters:
    ///   - xUnit: the unit of the abscissas ("Hz"); it gets a prefix on a linear axis (kHz).
    ///   - yUnit: the unit of the values when they are not in decibels ("°", "s").
    ///   - yScale: how the values are drawn, when there is no controller to say it; the values are magnitudes for decibels.
    ///   - controller: that of a window that has a toolbar of its own: it carries the scales, and the toolbar shows the menus.
    ///   - yScaleSwitchable: whether the toolbar offers decibels for the vertical axis (not for a phase).
    public init(curves: [PlotCurve], viewport: Binding<PlotViewport>, xUnit: String = "Hz", yUnit: String = "", yScale: AmplitudeScale = .linear,
                accent: Color = .accentColor, labels: PlotLabels = PlotLabels(), controller: PlotController? = nil, yScaleSwitchable: Bool = true,
                previewHover: CGPoint? = nil, previewMeasure: (x0: Double, y0: Double, x1: Double, y1: Double)? = nil) {
        self.curves = curves
        _viewport = viewport
        self.xUnit = xUnit
        self.yUnit = yUnit
        self.yScale = yScale
        self.accent = accent
        self.labels = labels
        self.controller = controller
        self.yScaleSwitchable = yScaleSwitchable
        self.previewHover = previewHover
        self.previewMeasure = previewMeasure.map { PlotSegment(x0: $0.x0, y0: $0.y0, x1: $0.x1, y1: $0.y1) }
    }

    /// The curves as they are drawn: the phases unwrapped when the inspector says so.
    private var shown: [PlotCurve] { (controller?.display.unwrapPhase ?? false) ? curves.map { $0.unwrapped() } : curves }

    private var effectiveYScale: AmplitudeScale { yScaleSwitchable ? (controller?.yScale ?? yScale) : yScale }

    public var body: some View {
        PlotView(content: CurveContent(curves: shown, yScale: effectiveYScale, xUnitText: xUnit, yUnitText: yUnit, gradient: controller?.display.gradient ?? PlotGradient()), viewport: $viewport,
                 accent: accent, labels: labels, controller: controller, previewHover: previewHover, previewMeasure: previewMeasure, previewBox: nil)
            .onAppear {
                guard let controller else { return }
                controller.hasPhase = curves.contains { $0.phase != nil }
                controller.scaleSupport = yScaleSwitchable ? [.x, .y] : [.x]
                controller.xScale = viewport.x.scale
                if yScaleSwitchable { controller.yScale = yScale }
            }
            .onChange(of: controller?.xScale) { _, new in
                guard let new, new != viewport.x.scale else { return }
                // The scale changes, the part that is shown stays as close as it can; a logarithmic axis starts at the first positive abscissa.
                let positive = curves.flatMap { $0.x.prefix($0.count) }.filter { $0 > 0 }.min() ?? 1e-3
                let span = viewport.x.bounds.upperBound - viewport.x.bounds.lowerBound
                viewport.x = viewport.x.switched(to: new, minSpan: new == .logarithmic ? 1.01 : span * 1e-4, positiveFloor: positive)
            }
            .onChange(of: controller?.display.unwrapPhase) { _, _ in
                // Unwrapped, a phase runs over thousands of degrees: the vertical axis is fitted again.
                viewport.y = PlotViewport.curves(shown, xScale: viewport.x.scale, yScale: effectiveYScale).y
            }
            .onChange(of: controller?.yScale) { _, new in
                guard yScaleSwitchable, let new else { return }
                // The values are not in the same units any more: the vertical axis is fitted again.
                viewport.y = PlotViewport.curves(curves, xScale: viewport.x.scale, yScale: new).y
            }
    }
}
