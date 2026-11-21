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

/// What a field of the table can be set for many impulse responses at once.
public enum BulkField: Sendable {
    case gain, delay, offset, length
}

/// Whether the value replaces the one of each impulse response, or is added to it (so that the differences between them stay).
public enum BulkMode: Sendable {
    case replace, shift
}

extension ConvDocument {
    /// Sets a field of the impulse responses of some pairs. The gain is in dB; delay, start and length are in samples and do not go
    /// under 0. Start and length belong to the files only. A copy has nothing of its own to set.
    /// - Returns: how many impulse responses changed.
    @discardableResult
    public mutating func bulkSet(_ field: BulkField, _ mode: BulkMode, value: Double, on pairs: [ConvPair]) -> Int {
        var changed = 0
        for pair in pairs {
            guard var list = content.impulses[pair] else { continue }
            for k in list.indices {
                var impulse = list[k]
                let isFile: Bool = { if case .file = impulse.source { return true } else { return false } }()
                let isCopy: Bool = { if case .copy = impulse.source { return true } else { return false } }()
                if isCopy { continue }
                switch field {
                case .gain:
                    impulse.gainDB = mode == .replace ? value : impulse.gainDB + value
                case .delay:
                    impulse.delay = max(0, Int((mode == .replace ? value : Double(impulse.delay) + value).rounded()))
                case .offset:
                    guard isFile else { continue }
                    impulse.offset = max(0, Int((mode == .replace ? value : Double(impulse.offset) + value).rounded()))
                case .length:
                    guard isFile else { continue }
                    impulse.length = max(0, Int((mode == .replace ? value : Double(impulse.length) + value).rounded()))
                }
                if field == .gain { impulse.gain = (impulse.gain * 1e6).rounded() / 1e6 }
                if impulse != list[k] { list[k] = impulse; changed += 1 }
            }
            content.impulses[pair] = list
        }
        return changed
    }
}

/// What is copied from the matrix: the impulse responses of some pairs, each with its place counted from the first of them.
public struct ClipboardItem: Equatable, Sendable {
    public var inputOffset: Int
    public var outputOffset: Int
    public var impulses: [ConvImpulse]
}

extension ConvDocument {
    /// The impulse responses of the pairs, with their places counted from the top left of the block that holds the pairs.
    public func copyOut(_ pairs: [ConvPair]) -> [ClipboardItem] {
        let filled = pairs.filter { !impulses(at: $0).isEmpty }
        guard let i0 = filled.map(\.input).min(), let o0 = filled.map(\.output).min() else { return [] }
        return filled.sorted().map { ClipboardItem(inputOffset: $0.input - i0, outputOffset: $0.output - o0, impulses: impulses(at: $0)) }
    }

    /// Puts what was copied with its top left on a pair. What goes beyond the matrix is left out; what was on a pair is replaced.
    /// A copy of another pair (`/impulse/copy`) keeps pointing at the same pair.
    /// - Returns: how many pairs were filled.
    @discardableResult
    public mutating func paste(_ items: [ClipboardItem], at start: ConvPair) -> Int {
        var count = 0
        for item in items {
            let pair = ConvPair(input: start.input + item.inputOffset, output: start.output + item.outputOffset)
            guard pair.input >= 0, pair.input < inputCount, pair.output >= 0, pair.output < outputCount else { continue }
            clear(pair)
            for impulse in item.impulses { add(impulse, at: pair) }
            count += 1
        }
        return count
    }

    /// The pairs that use the same sound file as an impulse response (for "select everything that uses this file").
    public func pairs(usingFileOf impulse: ConvImpulse, configDirectory: String) -> [ConvPair] {
        guard case .file(let file, _) = impulse.source else { return [] }
        let target = ConvConfig.path(of: file, directory: impulse.directory, configDirectory: configDirectory)
        return content.impulses.compactMap { pair, list in
            list.contains { other in
                guard case .file(let f, _) = other.source else { return false }
                return ConvConfig.path(of: f, directory: other.directory, configDirectory: configDirectory) == target
            } ? pair : nil
        }.sorted()
    }
}
