// SPDX-License-Identifier: MIT

import Foundation

/// What the plot reads: a signal that can say how many samples it has, the value of one, and the extremes of each column of
/// a window. The pyramid of a signal that is complete is one; a signal that grows while it is recorded (the history of a
/// level, an oscilloscope) can be another, without a change in the view.
public protocol PlotSignal: AnyObject, Sendable {
    var count: Int { get }
    func sample(at index: Int) -> Float
    func envelope(from x0: Double, to x1: Double, columns: Int, into e: inout Envelope)
}

/// How the amplitude is drawn: as it is, or as decibels of its magnitude.
public enum AmplitudeScale: Hashable, Sendable {
    case linear
    /// Decibels relative to 1, from `floor` (what is lower is drawn at the floor).
    case decibels(floor: Double)

    public var unit: String { self == .linear ? "" : "dB" }
    public var isDecibels: Bool { self != .linear }

    /// The value of a sample on the vertical axis.
    public func value(_ v: Float) -> Double {
        switch self {
        case .linear: return Double(v)
        case .decibels(let floor):
            let m = abs(Double(v))
            return m > 0 ? max(floor, 20 * log10(m)) : floor
        }
    }

    /// The same for a value that is not a sample (the magnitude of a spectrum, say).
    public func value(_ v: Double) -> Double {
        switch self {
        case .linear: return v
        case .decibels(let floor):
            let m = abs(v)
            return m > 0 ? max(floor, 20 * log10(m)) : floor
        }
    }

    /// The vertical axis for this scale.
    public func axis() -> AxisState {
        switch self {
        case .linear: return AxisState(bounds: -1.05...1.05, minSpan: 1e-5)
        case .decibels(let floor): return AxisState(bounds: floor...6, minSpan: 2)
        }
    }
}

extension PlotViewport {
    /// The view that shows a whole signal of `count` samples: the horizontal axis in samples (the labels turn them into time
    /// when the plot is given a sample rate), the vertical axis as the scale says.
    public static func signal(count: Int, amplitude: AmplitudeScale = .linear) -> PlotViewport {
        PlotViewport(x: AxisState(bounds: 0...Double(max(1, count - 1)), minSpan: 4), y: amplitude.axis())
    }
}

/// The texts of the plot, so that an application can give them in its language.
public struct PlotLabels: Sendable {
    public var zoomBox = "Zoom to a box"
    public var pan = "Pan"
    public var measure = "Measure"
    public var zoomIn = "Zoom in"
    public var zoomOut = "Zoom out"
    /// Added to the help of the zoom buttons.
    public var zoomModifiers = "⌥-click: vertical axis, ⇧-click: both axes"
    public var autoscale = "Autoscale vertical axis"
    public var reset = "Show everything"
    public var samples = "samples"
    public var inspector = "Inspector"
    public var display = "Display"
    public var phase = "Phase"
    public var fill = "Fill"
    public var phaseCurve = "Phase curve"
    public var smoothingBand = "Band"
    public var moreDetails = "More details"
    public var groupDelay = "Group delay"
    public var groupDelayHelp = "Shows the group delay in milliseconds (minus the slope of the unwrapped phase) instead of the phase."
    public var smoothing = "Smoothing"
    public var noSmoothing = "None"
    public var showUnsmoothed = "Show unsmoothed"
    public var smoothingHelp = "Averages the power in a band of a fraction of an octave around each frequency: what is read is the energy per band."
    public var removeDelay = "Remove delay"
    public var delayFitted = "fitted"
    public var delayGiven = "direct sound"
    public var removeDelayHelp = "Takes the delay out of the phase (the straight line it makes), so that what is left is the phase of the system itself."
    public var unwrapPhase = "Unwrap phase"
    public var unwrapPhaseHelp = "Adds whole turns so that the phase is continuous, without the jumps between −180° and +180°."
    public var gradientUnderCurve = "Gradient fill"
    public var fillStyle = "Style"
    public var fillGradient = "Gradient"
    public var fillFlat = "Flat"
    public var fillNone = "None"
    public var gradientWithSeveral = "Also with several curves"
    public var gradientHelp = "The body of a curve seen as an envelope (more samples than pixels) is filled, with a gradient or in one colour. With several curves it is opaque by default: the one on top hides the ones under it, and gradients over each other compete. Zoomed in until the samples are drawn one by one, there is no fill."
    public var channels = "Channels"
    public var allChannels = "All"
    public var noChannels = "None"
    public var onlyChannel = "Only"
    public var toFront = "Bring to front"
    public var channelsHelp = "Drag to reorder. The first is drawn on top of the others."
    public var xAxis = "Horizontal axis"
    public var yAxis = "Vertical axis"
    public var linear = "Linear"
    public var logarithmic = "Logarithmic"
    public var decibels = "Decibels"
    public var gesturesTitle = "Gestures of the plot"
    public var gestures = PlotGestureSection.defaults
    public init() {}
}
