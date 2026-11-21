// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// What can be dropped on a pair of the matrix: a channel of a sound file, a pulse, or a Hilbert filter.
public enum Placeable: Hashable, Sendable {
    /// The path is the one that goes in the configuration file: the name of the file when it is in the folder of the
    /// configuration, else the whole path.
    case channel(path: String, channel: Int)
    case dirac
    case hilbert
}

/// How several things dropped at once follow each other from the pair they are dropped on.
public enum PlacementMode: Sendable {
    /// Along the outputs of an input, then on to the next input.
    case row
    /// Along the inputs of an output, then on to the next output.
    case column
    /// Down the diagonal: the next input and the next output.
    case diagonal
}

public struct PlacementPlan: Equatable, Sendable {
    public struct Item: Equatable, Sendable {
        public var pair: ConvPair
        public var what: Placeable
        public init(pair: ConvPair, what: Placeable) { self.pair = pair; self.what = what }
    }

    public var items: [Item]
    /// How many things did not find a pair: the matrix ended.
    public var left: Int
    public init(items: [Item], left: Int) { self.items = items; self.left = left }
}

public enum Placement {
    /// Where each of the things goes, from the pair they are dropped on. What goes beyond the matrix is counted in `left`.
    public static func plan(_ things: [Placeable], from start: ConvPair, mode: PlacementMode, inputs: Int, outputs: Int) -> PlacementPlan {
        var items: [PlacementPlan.Item] = []
        for (k, what) in things.enumerated() {
            let pair: ConvPair
            switch mode {
            case .row:
                let p = start.input * outputs + start.output + k
                pair = ConvPair(input: p / max(outputs, 1), output: p % max(outputs, 1))
            case .column:
                let p = start.output * inputs + start.input + k
                pair = ConvPair(input: p % max(inputs, 1), output: p / max(inputs, 1))
            case .diagonal:
                pair = ConvPair(input: start.input + k, output: start.output + k)
            }
            if pair.input >= inputs || pair.output >= outputs || pair.input < 0 || pair.output < 0 { break }
            items.append(.init(pair: pair, what: what))
        }
        return PlacementPlan(items: items, left: things.count - items.count)
    }
}

extension ConvDocument {
    /// What a Hilbert filter dropped on a pair is: 512 samples long, with the delay that its centre needs (half its length) and a
    /// whole partition on top, so that nothing is cut by a latency compensation of one partition.
    public static let hilbertLength = 512

    /// Places what the plan says. A pair takes one impulse response, so what was on it is replaced.
    /// - Parameter partition: the partition of the convolver, for the delay of a Hilbert filter.
    /// - Returns: how many were placed, and how many of them replaced something.
    @discardableResult
    public mutating func apply(_ plan: PlacementPlan, partition: Int) -> (placed: Int, replaced: Int) {
        var replaced = 0
        for item in plan.items {
            if !impulses(at: item.pair).isEmpty { replaced += 1 }
            clear(item.pair)
            switch item.what {
            case .channel(let path, let channel): add(ConvImpulse(source: .file(path: path, channel: channel)), at: item.pair)
            case .dirac: add(ConvImpulse(source: .dirac), at: item.pair)
            case .hilbert:
                add(ConvImpulse(source: .hilbert(length: Self.hilbertLength), delay: partition + Self.hilbertLength / 2), at: item.pair)
            }
        }
        return (plan.items.count, replaced)
    }
}
