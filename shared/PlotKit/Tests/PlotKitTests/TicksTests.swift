// SPDX-License-Identifier: MIT

import XCTest
@testable import PlotKit

final class TicksTests: XCTestCase {
    private func majors(_ set: TickSet) -> [Double] { set.ticks.filter(\.isMajor).map(\.value) }

    func testNiceSteps() {
        XCTAssertEqual(majors(Ticks.linear(in: 0...1, approximately: 5)), [0, 0.2, 0.4, 0.6, 0.8, 1])
        XCTAssertEqual(majors(Ticks.linear(in: -1...1, approximately: 4)), [-1, -0.5, 0, 0.5, 1])
        XCTAssertEqual(majors(Ticks.linear(in: 0...100, approximately: 10)), (0...10).map { Double($0) * 10 })
        XCTAssertEqual(majors(Ticks.linear(in: 0...1_000_000, approximately: 6)), [0, 200_000, 400_000, 600_000, 800_000, 1_000_000])
        XCTAssertEqual(Ticks.linear(in: 0...1, approximately: 5).step, 0.2, accuracy: 1e-12)
    }

    func testNoFloatingPointDust() {
        for t in Ticks.linear(in: 0...0.5, approximately: 5).ticks {
            XCTAssertEqual(t.value, (t.value * 1e6).rounded() / 1e6, "\(t.value)")
        }
    }

    func testMinorTicks() {
        let set = Ticks.linear(in: 0...1, approximately: 5)   // major 0.2, four intervals
        XCTAssertEqual(set.ticks.count, 21)
        XCTAssertEqual(set.ticks.filter { !$0.isMajor }.count, 15)
        let five = Ticks.linear(in: 0...50, approximately: 5)  // major 10, five intervals
        XCTAssertEqual(five.ticks.count, 26)
    }

    func testTicksAreOrderedUniqueAndInsideTheRange() {
        var g = Lcg(state: 42)
        for _ in 0..<500 {
            let lo = (g.next() - 0.5) * pow(10, Double(Int(g.next() * 12) - 6))
            let span = pow(10, Double(Int(g.next() * 10) - 5)) * (0.1 + g.next())
            let target = 2 + Int(g.next() * 12)
            let set = Ticks.linear(in: lo...(lo + span), approximately: target)
            let values = set.ticks.map(\.value)
            XCTAssertEqual(values, values.sorted())
            XCTAssertEqual(Set(values).count, values.count, "range \(lo)...\(lo + span)")
            for v in values {
                XCTAssertGreaterThanOrEqual(v, lo - span * 1e-5)
                XCTAssertLessThanOrEqual(v, lo + span + span * 1e-5)
            }
            let n = majors(set).count
            XCTAssertLessThanOrEqual(n, target * 2 + 2, "range \(lo)...\(lo + span) target \(target)")
            XCTAssertGreaterThanOrEqual(n, max(1, target / 3), "range \(lo)...\(lo + span) target \(target)")
        }
    }

    func testDegenerateRanges() {
        XCTAssertTrue(Ticks.linear(in: 1...1, approximately: 5).ticks.isEmpty)
        XCTAssertTrue(Ticks.linear(in: 0...Double.infinity, approximately: 5).ticks.isEmpty)
        XCTAssertTrue(Ticks.linear(in: 0...1e12, approximately: 1_000_000).ticks.isEmpty, "absurd target: nothing, not a freeze")
        XCTAssertFalse(Ticks.linear(in: 1.0000001...1.0000002, approximately: 5).ticks.isEmpty)
        XCTAssertTrue(Ticks.logarithmic(in: 0...10).ticks.isEmpty)
    }

    func testLogarithmicTicks() {
        let set = Ticks.logarithmic(in: 20...20_000)
        let labelled = set.ticks.filter(\.isLabelled).map(\.value)
        XCTAssertEqual(labelled, [20, 50, 100, 200, 500, 1000, 2000, 5000, 10_000, 20_000])
        XCTAssertEqual(set.ticks.filter(\.isMajor).map(\.value), [100, 1000, 10_000])
        let wide = Ticks.logarithmic(in: 1e-3...1e9)   // twelve decades: only the decades, labelled every two
        XCTAssertTrue(wide.ticks.allSatisfy(\.isMajor))
        XCTAssertEqual(wide.ticks.filter(\.isLabelled).count, 7)
    }

    func testLabelsOfALinearAxis() {
        let set = Ticks.linear(in: 0...0.0025, approximately: 5)
        let labels = TickLabels.labels(for: set, unit: "s")
        XCTAssertEqual(labels.unit, "ms")
        XCTAssertEqual(labels.texts.filter { !$0.isEmpty }, ["0.0", "0.5", "1.0", "1.5", "2.0", "2.5"])
        let hertz = TickLabels.labels(for: Ticks.linear(in: 0...24_000, approximately: 6), unit: "Hz")
        XCTAssertEqual(hertz.unit, "kHz")
        XCTAssertEqual(hertz.texts.filter { !$0.isEmpty }, ["0", "5", "10", "15", "20"])
        let plain = TickLabels.labels(for: Ticks.linear(in: -1...1, approximately: 4))
        XCTAssertEqual(plain.texts.filter { !$0.isEmpty }, ["−1.0", "−0.5", "0.0", "0.5", "1.0"])
        XCTAssertEqual(plain.unit, "")
    }

    func testLabelsOfALogarithmicAxis() {
        let labels = TickLabels.labels(for: Ticks.logarithmic(in: 20...20_000), unit: "Hz")
        XCTAssertEqual(labels.texts.filter { !$0.isEmpty }, ["20", "50", "100", "200", "500", "1k", "2k", "5k", "10k", "20k"])
        XCTAssertEqual(labels.unit, "Hz")
    }

    func testNumberFormat() {
        XCTAssertEqual(TickLabels.number(-0.0001, decimals: 1), "0.0")
        XCTAssertEqual(TickLabels.number(-3, decimals: 0), "−3")
        XCTAssertEqual(TickLabels.number(1234.5, decimals: 1), "1234.5")
        XCTAssertEqual(SIPrefix.choose(for: 0.0042).symbol, "m")
        XCTAssertEqual(SIPrefix.choose(for: 0.00042).symbol, "µ")
        XCTAssertEqual(SIPrefix.choose(for: 5e-8).symbol, "n")
        XCTAssertEqual(SIPrefix.choose(for: 3.2e6).factor, 1e6)
    }
}

final class IntegerTicksTests: XCTestCase {
    func testSampleAxisTicksAreWholeNumbers() {
        for range in [0.0...3, 100.0...107, 0.0...47, 5000.0...5400, 0.0...480_000] {
            for t in Ticks.linear(in: range, approximately: 8, integersOnly: true).ticks {
                XCTAssertEqual(t.value, t.value.rounded(), "range \(range)")
            }
        }
        let tight = Ticks.linear(in: 10.0...13, approximately: 8, integersOnly: true)
        XCTAssertEqual(tight.ticks.map(\.value), [10, 11, 12, 13])
        XCTAssertTrue(tight.ticks.allSatisfy(\.isMajor))
        XCTAssertFalse(Ticks.linear(in: 0.0...1, approximately: 5).ticks.allSatisfy { $0.value == $0.value.rounded() })
    }
}
