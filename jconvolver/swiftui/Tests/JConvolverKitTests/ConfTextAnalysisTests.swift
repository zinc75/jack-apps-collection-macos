// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import JConvolverKit

final class ConfTextAnalysisTests: XCTestCase {
    private func problems(_ text: String) -> [ConfLineProblem] {
        ConfTextAnalysis.problems(in: text, configDirectory: "/tmp", fileInfo: { _ in nil }, jackRate: nil)
    }

    func testAGoodTextWithoutFilesHasNothingToSay() {
        XCTAssertEqual(problems("/convolver/new 1 1 256 1024 1\n/impulse/dirac 1 1 1 0\n"), [])
    }

    func testALineThatTheProgramRefusesIsReportedWhereItIs() {
        let list = problems("/convolver/new 1 1 256 1024 1\n/impulse/dirac one 1 1 0\n")
        XCTAssertEqual(list.map(\.line), [2])
        XCTAssertTrue(list[0].isError)
    }

    func testAFileThatCannotBeReadIsReportedOnItsLine() {
        let list = problems("/convolver/new 1 1 256 1024 1\n/cd /nowhere\n/impulse/read 1 1 1 0 0 0 1 missing.wav\n")
        XCTAssertEqual(list.map(\.line), [3])
        XCTAssertTrue(list[0].message.contains("missing.wav"))
    }

    func testATextThatIsNotAConfigurationIsSaidOnTheFirstLine() {
        let list = problems("hello\n")
        XCTAssertTrue(list.contains { $0.line == 1 && $0.isError })
    }

    func testAnEmptyTextHasNothingToSayYet() {
        XCTAssertEqual(problems(""), [])
    }
}
