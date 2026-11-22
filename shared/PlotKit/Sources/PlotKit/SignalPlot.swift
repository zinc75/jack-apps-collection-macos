// SPDX-License-Identifier: MIT

import SwiftUI

/// A plot of a signal in time for scientific use: graduated axes that follow the size of the view, the envelope of a signal of
/// millions of samples (and its samples one by one when it is zoomed in), a crosshair with the values, and the controls of Plotly
/// (see `PlotView` for the gestures). The horizontal axis is in samples, or in time when the sample rate is given.
public struct SignalPlot: View {
    let traces: [PlotTrace]
    @Binding var viewport: PlotViewport
    var sampleRate: Double?
    var amplitude: AmplitudeScale
    var accent: Color
    var labels: PlotLabels
    var controller: PlotController?
    var previewHover: CGPoint?
    var previewMeasure: PlotSegment?
    var previewBox: PlotMeasure?

    /// - Parameters:
    ///   - controller: that of a window that has a toolbar of its own (`PlotToolbarContent`); without one, the plot has a strip of its own.
    ///   - previewHover: a pointer position to draw the crosshair at without a pointer (for previews and tests).
    ///   - previewMeasure: a measure to show without a drag: two samples and their levels.
    ///   - previewBox: a box of a zoom to show without a drag: two points of the view.
    public init(signal: PlotSignal, viewport: Binding<PlotViewport>, sampleRate: Double? = nil, amplitude: AmplitudeScale = .linear,
                accent: Color = .accentColor, labels: PlotLabels = PlotLabels(), controller: PlotController? = nil, previewHover: CGPoint? = nil,
                previewMeasure: (x0: Double, y0: Double, x1: Double, y1: Double)? = nil, previewBox: (CGPoint, CGPoint)? = nil) {
        self.init(traces: [PlotTrace(name: "", signal: signal)], viewport: viewport, sampleRate: sampleRate, amplitude: amplitude, accent: accent,
                  labels: labels, controller: controller, previewHover: previewHover, previewMeasure: previewMeasure, previewBox: previewBox)
    }

    /// Several signals over each other, the channels of a file for instance: each in its colour, named in the card of the crosshair.
    public init(traces: [PlotTrace], viewport: Binding<PlotViewport>, sampleRate: Double? = nil, amplitude: AmplitudeScale = .linear,
                accent: Color = .accentColor, labels: PlotLabels = PlotLabels(), controller: PlotController? = nil, previewHover: CGPoint? = nil,
                previewMeasure: (x0: Double, y0: Double, x1: Double, y1: Double)? = nil, previewBox: (CGPoint, CGPoint)? = nil) {
        self.traces = traces
        _viewport = viewport
        self.sampleRate = sampleRate
        self.amplitude = amplitude
        self.accent = accent
        self.labels = labels
        self.controller = controller
        self.previewHover = previewHover
        self.previewBox = previewBox.map { PlotMeasure(a: $0.0, b: $0.1) }
        self.previewMeasure = previewMeasure.map { PlotSegment(x0: $0.x0, y0: $0.y0, x1: $0.x1, y1: $0.y1) }
    }

    /// With a controller, the toolbar sets how the amplitude is drawn (linear or decibels), as it sets the scales of a spectrum.
    private var effectiveAmplitude: AmplitudeScale { controller?.yScale ?? amplitude }

    public var body: some View {
        PlotView(content: SignalContent(traces: traces, sampleRate: sampleRate, amplitude: effectiveAmplitude), viewport: $viewport, accent: accent,
                 labels: labels, controller: controller, previewHover: previewHover, previewMeasure: previewMeasure, previewBox: previewBox)
            .onAppear {
                guard let controller else { return }
                controller.scaleSupport = [.y]
                controller.yScale = amplitude
            }
            .onChange(of: controller?.yScale) { _, new in
                // The levels are not in the same units any more: the vertical axis is fitted again.
                if let new, new != amplitude { viewport.y = new.axis() }
            }
    }
}
