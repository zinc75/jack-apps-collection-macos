// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import ZitaBridgeKit

@MainActor
final class LinkModelsTests: XCTestCase {
    private func receiver() -> ReceiverModel {
        var s = ReceiveSettings(); s.address = "10.10.10.1"
        return ReceiverModel(settings: s, executable: nil)
    }

    private func stats(_ frames: Int) -> LinkEvent { .statistics(LinkStatistics(periods: 48, meanError: 0, ratio: 1, frames: frames)) }

    private func linked(_ m: ReceiverModel) {
        for e: LinkEvent in [.waitingForSender, .senderFound(address: "10.10.10.2", channels: 2, rate: 48000), .filterDelay(32), .syncing, .receiving] { m.handle(e) }
    }

    func testTheStatesFollowWhatTheReceiverSays() {
        let m = receiver()
        XCTAssertEqual(m.state, .stopped)
        m.handle(.waitingForSender); XCTAssertEqual(m.state, .waiting)
        m.handle(.senderFound(address: "10.10.10.2", channels: 8, rate: 44100))
        XCTAssertEqual(m.sender, SenderInfo(address: "10.10.10.2", channels: 8, rate: 44100))
        XCTAssertEqual(m.state, .waiting, "heard, but not yet adjusted")
        m.handle(.filterDelay(48)); XCTAssertEqual(m.filterDelay, 48)
        m.handle(.syncing); XCTAssertEqual(m.state, .syncing)
        m.handle(.receiving); XCTAssertEqual(m.state, .linked)
        XCTAssertTrue(m.state.isRunning)
    }

    func testTheMarginIsInMillisecondsAtTheRateOfTheSender() {
        let m = receiver()
        m.handle(stats(960))
        XCTAssertNil(m.margin, "the rate of the sender is not known yet")
        linked(m)
        m.handle(stats(960))
        XCTAssertEqual(try XCTUnwrap(m.margin), 20, accuracy: 1e-9)
        XCTAssertEqual(m.marginHistory, [20])
    }

    func testTheHistoryKeepsTheLastMinute() {
        let m = receiver(); linked(m)
        for i in 0..<(ReceiverModel.historyLength + 30) { m.handle(stats(480 + i)) }
        XCTAssertEqual(m.marginHistory.count, ReceiverModel.historyLength)
        XCTAssertEqual(try XCTUnwrap(m.marginHistory.last), Double(480 + ReceiverModel.historyLength + 29) / 48, accuracy: 1e-9)
    }

    func testARunOfDryLinesIsOneInterruption() {
        let m = receiver(); linked(m)
        m.handle(stats(200)); m.handle(stats(-5)); m.handle(stats(-40)); m.handle(stats(-3))
        XCTAssertEqual(m.interruptions, 1)
        m.handle(stats(150)); m.handle(stats(-1))
        XCTAssertEqual(m.interruptions, 2, "a second one, after the queue recovered")
        m.resetInterruptions()
        XCTAssertEqual(m.interruptions, 0)
    }

    func testStartingAgainAfterALossCountsAsAnInterruption() {
        let m = receiver(); linked(m)
        m.handle(.retrying(seconds: 10))
        XCTAssertEqual(m.interruptions, 1)
        XCTAssertEqual(m.state, .waiting); XCTAssertEqual(m.retryDelay, 10)
        m.handle(.syncing); XCTAssertNil(m.retryDelay)
    }

    func testWaitingForTheFirstSenderIsNotAnInterruption() {
        let m = receiver()
        m.handle(.waitingForSender); m.handle(.retrying(seconds: 5))
        XCTAssertEqual(m.interruptions, 0)
    }

    func testASenderThatStopsLetsTheReceiverWaitAgain() {
        let m = receiver(); linked(m)
        m.handle(.transmitterEnded)
        XCTAssertEqual(m.state, .waiting); XCTAssertNil(m.sender)
        XCTAssertEqual(m.interruptions, 0)
    }

    func testAReasonToFailIsKept() {
        let m = receiver()
        m.handle(.error("Can't connect to Jack, is the server running ?"))
        XCTAssertEqual(m.state, .failed("Can't connect to Jack, is the server running ?"))
        XCTAssertFalse(m.state.isRunning)
        m.handle(.exited(status: 1, requested: false))
        XCTAssertEqual(m.state, .failed("Can't connect to Jack, is the server running ?"), "the end does not hide the reason")
    }

    func testTheEndThatWasAskedForIsAStop() {
        let m = receiver(); linked(m)
        m.handle(.exited(status: 130, requested: true))
        XCTAssertEqual(m.state, .stopped); XCTAssertNil(m.margin)
        let n = receiver(); linked(n)
        n.handle(.exited(status: 3, requested: false))
        XCTAssertEqual(n.state, .failed("zita-n2j ended with status 3"))
    }

    func testWarningsGoToTheLogWhichIsBounded() {
        let m = receiver()
        for i in 0..<80 { m.handle(.warning("w\(i)")) }
        XCTAssertEqual(m.log.count, 50); XCTAssertEqual(m.log.last, "w79")
        XCTAssertEqual(m.state, .stopped, "a warning does not change the state")
    }

    func testTheModelCannotStartWithoutTheProgramOrWithBadSettings() {
        let m = ReceiverModel(settings: ReceiveSettings(), executable: nil)   // no address
        XCTAssertFalse(m.canStart)
        m.start(); XCTAssertEqual(m.state, .stopped)
        var s = ReceiveSettings(); s.address = "10.10.10.1"
        let n = ReceiverModel(settings: s, executable: nil)
        XCTAssertTrue(n.canStart)
        n.start(); XCTAssertEqual(n.state, .failed("zita-n2j was not found"))
    }

    // MARK: The sender

    func testTheSenderOnlyKnowsThatItRuns() {
        var s = SendSettings(); s.address = "10.10.10.1"
        let m = SenderModel(settings: s, executable: nil)
        XCTAssertTrue(m.canStart)
        m.handle(.waitingForSender)   // not its lines: ignored
        XCTAssertEqual(m.state, .stopped)
        m.handle(.error("Address resolution failed."))
        XCTAssertEqual(m.state, .failed("Address resolution failed."))
        m.handle(.exited(status: 1, requested: false))
        XCTAssertEqual(m.state, .failed("Address resolution failed."))
        m.start(); XCTAssertEqual(m.state, .failed("zita-j2n was not found"))
    }
}
