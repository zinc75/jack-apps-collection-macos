// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import JConvolverKit

final class MatrixEditingTests: XCTestCase {
    private func p(_ i: Int, _ o: Int) -> ConvPair { ConvPair(input: i, output: o) }

    // MARK: Selection

    func testAClickSelectsOnePair() {
        var s = MatrixSelection()
        s.select(p(2, 3))
        XCTAssertEqual(s.pairs, [p(2, 3)])
        XCTAssertTrue(s.isSingle)
        XCTAssertTrue(s.contains(p(2, 3)))
        XCTAssertFalse(s.contains(p(2, 2)))
    }

    func testADragSelectsTheBlockBetweenTwoPairsWhicheverWayItGoes() {
        var s = MatrixSelection()
        s.select(from: p(3, 4), to: p(1, 2))
        XCTAssertEqual(s.count, 9)
        XCTAssertTrue(s.contains(p(2, 3)))
        XCTAssertFalse(s.contains(p(0, 3)))
        XCTAssertEqual(s.bounds, MatrixSelection.Block(from: p(1, 2), to: p(3, 4)))
    }

    func testShiftExtendsFromTheLastPairClicked() {
        var s = MatrixSelection()
        s.select(p(1, 1))
        s.extend(to: p(3, 2))
        XCTAssertEqual(s.count, 6)
        s.extend(to: p(0, 0))   // from the same anchor, not from the last extension
        XCTAssertEqual(s.count, 4)
        XCTAssertEqual(s.anchor, p(1, 1))
    }

    func testCommandPicksPairsOneByOne() {
        var s = MatrixSelection()
        s.select(p(1, 1))
        s.toggle(p(3, 4))
        s.toggle(p(5, 2))
        XCTAssertEqual(s.count, 3)
        XCTAssertEqual(s.pairs, [p(1, 1), p(3, 4), p(5, 2)])
        XCTAssertEqual(s.bounds, MatrixSelection.Block(from: p(1, 1), to: p(5, 4)))   // for what needs a rectangle
        s.toggle(p(3, 4))
        XCTAssertEqual(s.pairs, [p(1, 1), p(5, 2)])
    }

    func testTheLastPairCannotBeTakenOut() {
        var s = MatrixSelection()
        s.select(p(1, 1))
        s.toggle(p(1, 1))
        XCTAssertEqual(s.pairs, [p(1, 1)])
        s.toggle(p(2, 2))
        s.toggle(p(2, 2))
        XCTAssertEqual(s.pairs, [p(1, 1)])
        XCTAssertTrue(s.isSingle)
    }

    func testAToggleOnAPairInsideABlockTakesItOut() {
        var s = MatrixSelection()
        s.select(from: p(0, 0), to: p(1, 1))
        s.toggle(p(0, 1))
        XCTAssertEqual(s.pairs, [p(0, 0), p(1, 0), p(1, 1)])
    }

    func testRowColumnAndEverything() {
        var s = MatrixSelection()
        s.selectInput(2, outputs: 8)
        XCTAssertEqual(s.count, 8)
        XCTAssertTrue(s.contains(p(2, 7)))
        s.selectOutput(5, inputs: 16)
        XCTAssertEqual(s.count, 16)
        XCTAssertTrue(s.contains(p(15, 5)))
        s.selectAll(inputs: 4, outputs: 3)
        XCTAssertEqual(s.count, 12)
    }

    func testWhenTheMatrixShrinksWhatIsOutsideGoes() {
        var s = MatrixSelection()
        s.select(from: p(0, 0), to: p(3, 3))
        s.clamp(inputs: 2, outputs: 2)
        XCTAssertEqual(s.pairs, [p(0, 0), p(0, 1), p(1, 0), p(1, 1)])
        s.select(p(5, 5))
        s.clamp(inputs: 2, outputs: 2)
        XCTAssertEqual(s.pairs, [p(0, 0)])
    }

    // MARK: History

    private func document(_ gain: Double) -> ConvDocument {
        var d = ConvDocument(inputs: 1, outputs: 1)
        d.add(ConvImpulse(source: .dirac, gain: gain), at: p(0, 0))
        return d
    }

    func testUndoAndRedoGoBackAndForth() {
        var h = DocumentHistory()
        var current = document(1)
        h.record("gain", before: current); current = document(2)
        h.record("gain", before: current); current = document(3)
        XCTAssertEqual(h.undoLabel, "gain")
        let back = h.undo(current: current)
        XCTAssertEqual(back?.document.impulses(at: p(0, 0)).first?.gain, 2)
        current = back!.document
        XCTAssertTrue(h.canRedo)
        let forth = h.redo(current: current)
        XCTAssertEqual(forth?.document.impulses(at: p(0, 0)).first?.gain, 3)
    }

    func testANewChangeEndsTheRedo() {
        var h = DocumentHistory()
        h.record("a", before: document(1))
        _ = h.undo(current: document(2))
        XCTAssertTrue(h.canRedo)
        h.record("b", before: document(1))
        XCTAssertFalse(h.canRedo)
    }

    func testNothingToUndo() {
        var h = DocumentHistory()
        XCTAssertFalse(h.canUndo)
        XCTAssertNil(h.undo(current: document(1)))
        XCTAssertNil(h.redo(current: document(1)))
    }

    func testTheHistoryIsLimited() {
        var h = DocumentHistory()
        h.capacity = 3
        for i in 0..<5 { h.record("c\(i)", before: document(Double(i))) }
        XCTAssertEqual(h.undoSteps.count, 3)
        XCTAssertEqual(h.undoLabel, "c4")
        XCTAssertEqual(h.undoSteps.first?.label, "c2")
    }

    // MARK: Placement

    private func channels(_ n: Int) -> [Placeable] { (1...n).map { .channel(path: "a.wav", channel: $0) } }

    func testAlongARow() {
        let plan = Placement.plan(channels(3), from: p(1, 2), mode: .row, inputs: 3, outputs: 4)
        XCTAssertEqual(plan.items.map(\.pair), [p(1, 2), p(1, 3), p(2, 0)])   // the row ends, the next input goes on
        XCTAssertEqual(plan.left, 0)
    }

    func testAlongAColumn() {
        let plan = Placement.plan(channels(4), from: p(1, 0), mode: .column, inputs: 3, outputs: 4)
        XCTAssertEqual(plan.items.map(\.pair), [p(1, 0), p(2, 0), p(0, 1), p(1, 1)])
    }

    func testDownTheDiagonal() {
        let plan = Placement.plan(channels(3), from: p(0, 1), mode: .diagonal, inputs: 4, outputs: 4)
        XCTAssertEqual(plan.items.map(\.pair), [p(0, 1), p(1, 2), p(2, 3)])
    }

    func testWhatGoesBeyondTheMatrixIsCounted() {
        let diagonal = Placement.plan(channels(5), from: p(2, 2), mode: .diagonal, inputs: 4, outputs: 4)
        XCTAssertEqual(diagonal.items.count, 2)
        XCTAssertEqual(diagonal.left, 3)
        let row = Placement.plan(channels(5), from: p(1, 1), mode: .row, inputs: 2, outputs: 2)
        XCTAssertEqual(row.items.map(\.pair), [p(1, 1)])
        XCTAssertEqual(row.left, 4)
    }

    func testPlacingReplacesWhatWasThere() {
        var d = ConvDocument(inputs: 2, outputs: 2)
        d.add(ConvImpulse(source: .dirac), at: p(0, 0))
        d.add(ConvImpulse(source: .dirac, delay: 5), at: p(0, 0))
        let plan = Placement.plan(channels(2), from: p(0, 0), mode: .row, inputs: 2, outputs: 2)
        let result = d.apply(plan, partition: 256)
        XCTAssertEqual(result.placed, 2)
        XCTAssertEqual(result.replaced, 1)
        XCTAssertEqual(d.impulses(at: p(0, 0)).count, 1)
        XCTAssertEqual(d.impulses(at: p(0, 0)).first?.source, .file(path: "a.wav", channel: 1))
        XCTAssertEqual(d.impulses(at: p(0, 1)).first?.source, .file(path: "a.wav", channel: 2))
    }

    func testPulsesAndFiltersGetTheirOwnValues() {
        var d = ConvDocument(inputs: 1, outputs: 2)
        let plan = Placement.plan([.dirac, .hilbert], from: p(0, 0), mode: .row, inputs: 1, outputs: 2)
        d.apply(plan, partition: 256)
        XCTAssertEqual(d.impulses(at: p(0, 0)).first?.source, .dirac)
        let h = d.impulses(at: p(0, 1)).first
        XCTAssertEqual(h?.source, .hilbert(length: 512))
        XCTAssertEqual(h?.delay, 256 + 256)   // a partition, and half the length
        // And the validator is satisfied: the delay covers the half length.
        let problems = ConvValidator.problems(in: d, context: ConvValidationContext(mode: .realTime(jackRate: 48000), configDirectory: "/", fileInfo: { _ in nil }))
        XCTAssertFalse(problems.contains { if case .hilbertDelayTooSmall = $0.kind { return true } else { return false } })
    }

    // MARK: Table: a list of pairs, and a field set for many

    func testPickingAListOfPairs() {
        var s = MatrixSelection()
        s.pick([p(0, 0), p(2, 1), p(3, 3)])
        XCTAssertEqual(s.pairs, [p(0, 0), p(2, 1), p(3, 3)])
        XCTAssertEqual(s.anchor, p(3, 3))
        s.pick([p(1, 1)])
        XCTAssertTrue(s.isSingle)
        s.pick([])
        XCTAssertEqual(s.pairs, [p(1, 1)])
    }

    private func two() -> ConvDocument {
        var d = ConvDocument(inputs: 2, outputs: 2)
        d.add(ConvImpulse(source: .file(path: "a.wav", channel: 1), gain: 0.5, delay: 10, offset: 5, length: 100), at: p(0, 0))
        d.add(ConvImpulse(source: .file(path: "a.wav", channel: 2), gain: 0.25, delay: 0, offset: 0, length: 0), at: p(1, 1))
        d.add(ConvImpulse(source: .dirac, gain: 1, delay: 3), at: p(0, 1))
        d.add(ConvImpulse(source: .copy(of: p(0, 0))), at: p(1, 0))
        return d
    }

    func testReplacingAFieldForManyPairs() {
        var d = two()
        let n = d.bulkSet(.gain, .replace, value: -6, on: [p(0, 0), p(1, 1), p(0, 1), p(1, 0)])
        XCTAssertEqual(n, 3)   // the copy has nothing of its own
        XCTAssertEqual(d.impulses(at: p(0, 0)).first?.gainDB ?? 0, -6, accuracy: 1e-4)
        XCTAssertEqual(d.impulses(at: p(1, 1)).first?.gainDB ?? 0, -6, accuracy: 1e-4)
    }

    func testShiftingKeepsTheDifferencesBetweenImpulseResponses() {
        var d = two()
        let before = (d.impulses(at: p(0, 0)).first!.gainDB, d.impulses(at: p(1, 1)).first!.gainDB)
        d.bulkSet(.gain, .shift, value: -3, on: [p(0, 0), p(1, 1)])
        XCTAssertEqual(d.impulses(at: p(0, 0)).first!.gainDB, before.0 - 3, accuracy: 1e-4)
        XCTAssertEqual(d.impulses(at: p(1, 1)).first!.gainDB, before.1 - 3, accuracy: 1e-4)
        d.bulkSet(.delay, .shift, value: 5, on: [p(0, 0), p(1, 1), p(0, 1)])
        XCTAssertEqual(d.impulses(at: p(0, 0)).first?.delay, 15)
        XCTAssertEqual(d.impulses(at: p(1, 1)).first?.delay, 5)
        XCTAssertEqual(d.impulses(at: p(0, 1)).first?.delay, 8)
    }

    func testDelayStartAndLengthNeverGoUnderZero() {
        var d = two()
        d.bulkSet(.delay, .shift, value: -100, on: [p(0, 0)])
        d.bulkSet(.offset, .shift, value: -100, on: [p(0, 0)])
        d.bulkSet(.length, .shift, value: -1000, on: [p(0, 0)])
        let i = d.impulses(at: p(0, 0)).first
        XCTAssertEqual(i?.delay, 0)
        XCTAssertEqual(i?.offset, 0)
        XCTAssertEqual(i?.length, 0)
    }

    func testStartAndLengthBelongToFilesOnly() {
        var d = two()
        XCTAssertEqual(d.bulkSet(.offset, .replace, value: 50, on: [p(0, 1)]), 0)   // a pulse
        XCTAssertEqual(d.bulkSet(.length, .replace, value: 50, on: [p(0, 1), p(0, 0)]), 1)
        XCTAssertEqual(d.impulses(at: p(0, 1)).first?.length, 0)
    }

    func testNothingChangedIsNotCounted() {
        var d = two()
        XCTAssertEqual(d.bulkSet(.delay, .replace, value: 10, on: [p(0, 0)]), 0)
        XCTAssertEqual(d.bulkSet(.gain, .shift, value: 0, on: [p(0, 0)]), 0)
    }
}
