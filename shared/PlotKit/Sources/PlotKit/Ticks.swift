// SPDX-License-Identifier: MIT

import Foundation

/// A graduation of an axis.
public struct Tick: Equatable, Sendable {
    public var value: Double
    /// A major tick is drawn longer, and its grid line stronger.
    public var isMajor: Bool
    /// Whether it carries a label: the major ticks of a linear axis, and on a logarithmic axis the ones that fit.
    public var isLabelled: Bool
}

/// The graduations of an axis for a range, and the step they were made with.
public struct TickSet: Equatable, Sendable {
    public var ticks: [Tick]
    /// The distance of two major ticks of a linear axis (the ratio of two on a logarithmic one).
    public var step: Double
    public var isLogarithmic: Bool
}

public enum Ticks {
    /// A step of 1, 2 or 5 times a power of ten, the nearest to `raw`, and the number of minor intervals in it that read well
    /// (1 and 5 are cut in 5, 2 in 4).
    static func niceStep(_ raw: Double) -> (step: Double, minors: Int) {
        let magnitude = pow(10, floor(log10(raw)))
        let m = raw / magnitude
        // The limits are the geometric means of 1, 2, 5 and 10: the choice is the nearest on a logarithmic scale.
        if m >= 7.07 { return (10 * magnitude, 5) }
        if m >= 3.16 { return (5 * magnitude, 5) }
        if m >= 1.41 { return (2 * magnitude, 4) }
        return (magnitude, 5)
    }

    /// Graduations of a linear axis: about `target` major ticks, at multiples of 1, 2 or 5 times a power of ten, with minor
    /// ticks between them.
    public static func linear(in range: ClosedRange<Double>, approximately target: Int) -> TickSet {
        let span = range.upperBound - range.lowerBound
        guard span > 0, span.isFinite, range.lowerBound.isFinite else { return TickSet(ticks: [], step: 0, isLogarithmic: false) }
        let (step, minors) = niceStep(span / Double(max(1, target)))
        let minorStep = step / Double(minors)
        // Too many ticks (a target that is absurd for the span): none, rather than a freeze.
        guard span / minorStep < 2000 else { return TickSet(ticks: [], step: step, isLogarithmic: false) }
        let epsilon = minorStep * 1e-6
        var ticks: [Tick] = []
        var k = Int((range.lowerBound / minorStep - 1e-6).rounded(.up))
        while true {
            let value = clean(Double(k) * minorStep, step: minorStep)
            if value > range.upperBound + epsilon { break }
            let isMajor = k % minors == 0
            ticks.append(Tick(value: value == 0 ? 0 : value, isMajor: isMajor, isLabelled: isMajor))
            k += 1
        }
        return TickSet(ticks: ticks, step: step, isLogarithmic: false)
    }

    /// Graduations of a logarithmic axis (the range must be positive): a major tick at each power of ten, minor ticks at 2 to 9
    /// times it. Up to three decades the 2s and the 5s are labelled too; beyond eight decades only every few decades are.
    public static func logarithmic(in range: ClosedRange<Double>) -> TickSet {
        guard range.lowerBound > 0, range.upperBound > range.lowerBound, range.upperBound.isFinite else {
            return TickSet(ticks: [], step: 0, isLogarithmic: true)
        }
        let first = Int(floor(log10(range.lowerBound))), last = Int(ceil(log10(range.upperBound)))
        // The span in decades (20 to 20 000 is three, though it touches five powers of ten).
        let decades = log10(range.upperBound / range.lowerBound)
        let labelEvery = decades > 8 ? Int(ceil(decades / 8)) : 1
        var ticks: [Tick] = []
        for d in first...last {
            let base = pow(10, Double(d))
            let digits = decades > 8 ? [1] : Array(1...9)
            for digit in digits {
                let value = base * Double(digit)
                guard value >= range.lowerBound * (1 - 1e-9), value <= range.upperBound * (1 + 1e-9) else { continue }
                let isMajor = digit == 1
                var labelled = isMajor && (d - first) % labelEvery == 0
                if decades <= 3.0001 && (digit == 2 || digit == 5) { labelled = true }
                ticks.append(Tick(value: value, isMajor: isMajor, isLabelled: labelled))
            }
        }
        return TickSet(ticks: ticks, step: 10, isLogarithmic: true)
    }

    /// Removes the error of a product of floating point numbers: 0.30000000000000004 is 0.3.
    private static func clean(_ value: Double, step: Double) -> Double {
        let decimals = max(0, Int(-floor(log10(step) + 1e-9)) + 1)
        guard decimals < 15 else { return value }
        let scale = pow(10, Double(decimals))
        return (value * scale).rounded() / scale
    }
}

/// The text of the labels of an axis.
public struct AxisLabels: Equatable, Sendable {
    /// One text per tick, in order; empty for the ticks that have no label.
    public var texts: [String]
    /// What the labels are in, to write once on the axis ("ms", "kHz"); empty without a unit.
    public var unit: String
}

public enum TickLabels {
    /// The labels of a set of graduations. On a linear axis they share one unit prefix (µ, m, none, k, M), chosen by the
    /// largest value, and one number of decimals, the one the step needs. On a logarithmic axis each label has the prefix
    /// that suits it ("20", "500", "1k", "20k") and the unit stays apart. The minus sign is the mathematical one.
    public static func labels(for set: TickSet, unit baseUnit: String = "") -> AxisLabels {
        if set.isLogarithmic {
            return AxisLabels(texts: set.ticks.map { $0.isLabelled ? compact($0.value) : "" }, unit: baseUnit)
        }
        guard set.step > 0 else { return AxisLabels(texts: set.ticks.map { _ in "" }, unit: baseUnit) }
        let largest = set.ticks.map { abs($0.value) }.max() ?? 0
        let (factor, prefix) = baseUnit.isEmpty ? (1.0, "") : SIPrefix.choose(for: largest > 0 ? largest : set.step)
        let decimals = max(0, Int(-floor(log10(set.step / factor) + 1e-9)))
        let texts = set.ticks.map { tick -> String in
            guard tick.isLabelled else { return "" }
            return number(tick.value / factor, decimals: decimals)
        }
        return AxisLabels(texts: texts, unit: baseUnit.isEmpty ? "" : prefix + baseUnit)
    }

    /// A number with a fixed count of decimals, "−" for a negative one and never "−0".
    public static func number(_ value: Double, decimals: Int) -> String {
        var text = String(format: "%.\(decimals)f", value)
        if text.hasPrefix("-") {
            if text.dropFirst().allSatisfy({ $0 == "0" || $0 == "." }) { text.removeFirst() } else { text = "−" + text.dropFirst() }
        }
        return text
    }

    /// 20, 500, 1k, 20k, 1M: the shortest text of a positive value of a logarithmic axis.
    static func compact(_ value: Double) -> String {
        func trim(_ v: Double) -> String {
            let text = String(format: "%g", (v * 1e6).rounded() / 1e6)
            return text
        }
        if value >= 1e6 { return trim(value / 1e6) + "M" }
        if value >= 1e3 { return trim(value / 1e3) + "k" }
        if value >= 1 { return trim(value) }
        if value >= 1e-3 { return trim(value * 1e3) + "m" }
        return trim(value * 1e6) + "µ"
    }
}

public enum SIPrefix {
    /// The prefix that gives a number from 1 to 999 for this magnitude: the factor to divide the values by, and the symbol.
    public static func choose(for magnitude: Double) -> (factor: Double, symbol: String) {
        let m = abs(magnitude)
        if m >= 1e9 { return (1e9, "G") }
        if m >= 1e6 { return (1e6, "M") }
        if m >= 1e3 { return (1e3, "k") }
        if m >= 1 { return (1, "") }
        if m >= 1e-3 { return (1e-3, "m") }
        if m >= 1e-6 { return (1e-6, "µ") }
        return (1e-9, "n")
    }
}
