// SPDX-License-Identifier: MIT

import Observation
import SwiftUI

/// How the body of a curve is filled: a gradient that fades, or a flat translucent colour. The fill is always there (it is what
/// shows the waveform between its envelope lines); only its style is a choice.
public enum PlotFill: Equatable, Sendable {
    /// A gradient, at this strength (1 is the full one).
    case gradient(Double)
    /// A flat colour at this opacity.
    case flat(Double)
    /// An opaque body, in the colour mixed with the background (1 is the colour itself): what is drawn over it hides what is under
    /// it, as the oscillations of a curve drawn over another would.
    case solid(Double)
}

/// The style of the fill: a gradient for one curve; for several an opaque body by default, so that the curve that is on top is the
/// one that is seen (gradients over each other fight).
public struct PlotGradient: Equatable, Sendable {
    /// A gradient when one curve is shown (a flat fill when it is off).
    public var enabled = true
    /// And also when several are shown (the one on top still hides the ones under it).
    public var withSeveral = false

    public init(enabled: Bool = true, withSeveral: Bool = false) {
        self.enabled = enabled
        self.withSeveral = withSeveral
    }

    /// The fill for a number of curves.
    public func fill(curves count: Int) -> PlotFill {
        if count <= 1 { return enabled ? .gradient(1) : .flat(0.34) }
        return enabled && withSeveral ? .gradient(0.7) : .solid(0.5)
    }
}

/// The settings of how a plot looks, the ones that are not worth a button of the toolbar: they live in the inspector of the
/// window, as the format settings of an editor do. More come here with time.
@MainActor
@Observable
public final class PlotDisplayOptions {
    public var gradient = PlotGradient()
    /// A phase is drawn unwrapped (continuous) instead of between −180° and +180°.
    public var unwrapPhase = false
    /// The delay is taken out of a phase (the straight line it makes).
    public var removeDelay = false
    public init() {}
}

/// The inspector of a plot, in sections: the channels (when there are several) and the display options. The window puts it in
/// an inspector bound to `controller.showsInspector`, and the button of the toolbar shows and hides it.
public struct PlotInspector: View {
    @Bindable var controller: PlotController
    var labels: PlotLabels
    var accent: Color

    /// - Parameter accent: the accent of the application, for the boxes and the links (the system's keeps its own).
    public init(controller: PlotController, labels: PlotLabels = PlotLabels(), accent: Color = .accentColor) {
        self.controller = controller
        self.labels = labels
        self.accent = accent
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let series = controller.series, series.items.count > 1 {
                    PlotChannelList(series: series, labels: labels, inInspector: true)
                }
                display
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .tint(accent)
    }

    @ViewBuilder private var display: some View {
        @Bindable var options = controller.display
        VStack(alignment: .leading, spacing: 8) {
            Text(labels.display).font(.headline)
            Divider()
            Toggle(labels.gradientUnderCurve, isOn: $options.gradient.enabled)
            Toggle(labels.gradientWithSeveral, isOn: $options.gradient.withSeveral)
                .padding(.leading, 18)
                .disabled(!options.gradient.enabled)
            Text(labels.gradientHelp).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if controller.hasPhase {
                Divider().padding(.vertical, 4)
                Toggle(labels.unwrapPhase, isOn: $options.unwrapPhase)
                Text(labels.unwrapPhaseHelp).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Toggle(labels.removeDelay, isOn: $options.removeDelay).padding(.top, 4)
                Text(labels.removeDelayHelp).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                // The value that is taken out, for each phase, and where it comes from.
                ForEach(controller.phaseDelays, id: \.name) { d in
                    HStack(spacing: 6) {
                        Text(d.name).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(TickLabels.engineering(d.seconds, unit: "s")).monospacedDigit()
                        Text("(" + (d.isEstimated ? labels.delayFitted : labels.delayGiven) + ")").foregroundStyle(.secondary)
                    }
                    .font(.callout)
                    .foregroundStyle(options.removeDelay ? .primary : .secondary)
                }
            }
        }
        .toggleStyle(.checkbox)
    }
}
