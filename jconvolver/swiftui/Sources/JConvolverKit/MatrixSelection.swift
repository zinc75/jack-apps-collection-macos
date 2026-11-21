// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The pairs that are selected in the matrix: a rectangle (a click, a drag, a row, a column, everything) or a set of pairs picked
/// one by one (with the command key). The table shows the same selection.
public struct MatrixSelection: Equatable, Sendable {
    /// An inclusive block of the matrix.
    public struct Block: Equatable, Sendable {
        public var firstInput: Int, lastInput: Int
        public var firstOutput: Int, lastOutput: Int

        public init(from a: ConvPair, to b: ConvPair) {
            firstInput = min(a.input, b.input); lastInput = max(a.input, b.input)
            firstOutput = min(a.output, b.output); lastOutput = max(a.output, b.output)
        }

        public func contains(_ pair: ConvPair) -> Bool {
            (firstInput...lastInput).contains(pair.input) && (firstOutput...lastOutput).contains(pair.output)
        }

        public var count: Int { (lastInput - firstInput + 1) * (lastOutput - firstOutput + 1) }
    }

    public enum Shape: Equatable, Sendable {
        case block(Block)
        case picked(Set<ConvPair>)
    }

    public private(set) var shape: Shape
    /// The pair from which a shift-click extends: the last one that was clicked.
    public private(set) var anchor: ConvPair

    public init(_ pair: ConvPair = ConvPair(input: 0, output: 0)) {
        shape = .block(Block(from: pair, to: pair))
        anchor = pair
    }

    // MARK: What is selected

    public func contains(_ pair: ConvPair) -> Bool {
        switch shape {
        case .block(let b): return b.contains(pair)
        case .picked(let set): return set.contains(pair)
        }
    }

    public var count: Int {
        switch shape {
        case .block(let b): return b.count
        case .picked(let set): return set.count
        }
    }

    /// The smallest block that holds the selection: where a paste or a placement starts.
    public var bounds: Block {
        switch shape {
        case .block(let b): return b
        case .picked(let set):
            let inputs = set.map(\.input), outputs = set.map(\.output)
            return Block(from: ConvPair(input: inputs.min() ?? 0, output: outputs.min() ?? 0),
                         to: ConvPair(input: inputs.max() ?? 0, output: outputs.max() ?? 0))
        }
    }

    /// The pairs, by input and then by output.
    public var pairs: [ConvPair] {
        switch shape {
        case .block(let b):
            return (b.firstInput...b.lastInput).flatMap { i in (b.firstOutput...b.lastOutput).map { ConvPair(input: i, output: $0) } }
        case .picked(let set): return set.sorted()
        }
    }

    public var isSingle: Bool { count == 1 }

    // MARK: Changing it

    /// A click on a pair: only this one.
    public mutating func select(_ pair: ConvPair) {
        shape = .block(Block(from: pair, to: pair))
        anchor = pair
    }

    /// A drag from a pair to another: the block between them.
    public mutating func select(from a: ConvPair, to b: ConvPair) {
        shape = .block(Block(from: a, to: b))
        anchor = a
    }

    /// A shift-click: the block from the anchor to this pair.
    public mutating func extend(to pair: ConvPair) {
        shape = .block(Block(from: anchor, to: pair))
    }

    /// A command-click: this pair is added, or removed when it was there (the last one cannot be removed).
    public mutating func toggle(_ pair: ConvPair) {
        var set = Set(pairs)
        if set.contains(pair) { if set.count > 1 { set.remove(pair) } } else { set.insert(pair) }
        shape = set.count > 1 ? .picked(set) : .block(Block(from: set.first ?? pair, to: set.first ?? pair))
        anchor = pair
    }

    /// A list of pairs picked by hand (the rows of the table between two clicks): the selection is these pairs, and the last is the anchor.
    public mutating func pick(_ list: [ConvPair]) {
        guard let last = list.last else { return }
        let set = Set(list)
        if set.count == 1 { select(last); return }
        shape = .picked(set)
        anchor = last
    }

    /// The whole row of an input.
    public mutating func selectInput(_ input: Int, outputs: Int) {
        shape = .block(Block(from: ConvPair(input: input, output: 0), to: ConvPair(input: input, output: max(0, outputs - 1))))
        anchor = ConvPair(input: input, output: 0)
    }

    /// The whole column of an output.
    public mutating func selectOutput(_ output: Int, inputs: Int) {
        shape = .block(Block(from: ConvPair(input: 0, output: output), to: ConvPair(input: max(0, inputs - 1), output: output)))
        anchor = ConvPair(input: 0, output: output)
    }

    public mutating func selectAll(inputs: Int, outputs: Int) {
        shape = .block(Block(from: ConvPair(input: 0, output: 0), to: ConvPair(input: max(0, inputs - 1), output: max(0, outputs - 1))))
        anchor = ConvPair(input: 0, output: 0)
    }

    /// After the matrix has been resized: what is outside it goes, and when nothing is left the first pair is selected.
    public mutating func clamp(inputs: Int, outputs: Int) {
        let valid = pairs.filter { $0.input < inputs && $0.output < outputs }
        if valid.isEmpty { select(ConvPair(input: 0, output: 0)); return }
        if valid.count == count { return }
        shape = valid.count > 1 ? .picked(Set(valid)) : .block(Block(from: valid[0], to: valid[0]))
        anchor = valid[0]
    }
}

/// The history of the changes of a document, for undo and redo. A change is kept as the whole document before it: the matrix is
/// small, and a copy is cheap.
public struct DocumentHistory: Sendable {
    public struct Step: Sendable {
        public var label: String
        public var document: ConvDocument
    }

    public private(set) var undoSteps: [Step] = []
    public private(set) var redoSteps: [Step] = []
    public var capacity = 100

    public init() {}

    public var canUndo: Bool { !undoSteps.isEmpty }
    public var canRedo: Bool { !redoSteps.isEmpty }
    public var undoLabel: String? { undoSteps.last?.label }
    public var redoLabel: String? { redoSteps.last?.label }

    /// Records a change that is about to be made: the document as it is now.
    public mutating func record(_ label: String, before document: ConvDocument) {
        undoSteps.append(Step(label: label, document: document))
        if undoSteps.count > capacity { undoSteps.removeFirst(undoSteps.count - capacity) }
        redoSteps.removeAll()
    }

    /// The document before the last change; the current one is kept for a redo.
    public mutating func undo(current: ConvDocument) -> Step? {
        guard let step = undoSteps.popLast() else { return nil }
        redoSteps.append(Step(label: step.label, document: current))
        return step
    }

    public mutating func redo(current: ConvDocument) -> Step? {
        guard let step = redoSteps.popLast() else { return nil }
        undoSteps.append(Step(label: step.label, document: current))
        return step
    }

    public mutating func clear() {
        undoSteps.removeAll()
        redoSteps.removeAll()
    }
}
