// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import ZitaBridgeKit

final class LinkLogParserTests: XCTestCase {
    private func events(_ text: String) -> [LinkEvent] {
        var parser = LinkLogParser()
        return parser.feed(Data(text.utf8))
    }

    /// What a real receiver wrote in a pseudo-terminal, from the start to a few seconds of reception (isolated JACK server).
    func testARealSessionFromTheFirstLineToTheStatistics() {
        let session = """
        Warning: memory lock failed.\r
        Waiting for info packet...\r
        From 127.0.0.1 : 2 chan, 48000 Hz\r
        Resampler filter delay is 32.\r
        Syncing...\r
        Receiving.\r
         48   -0.092  1.000017      197\r
         47    0.215  0.999974      196\r

        """
        XCTAssertEqual(events(session), [
            .warning("Warning: memory lock failed."),
            .waitingForSender,
            .senderFound(address: "127.0.0.1", channels: 2, rate: 48000),
            .filterDelay(32),
            .syncing,
            .receiving,
            .statistics(LinkStatistics(periods: 48, meanError: -0.092, ratio: 1.000017, frames: 197)),
            .statistics(LinkStatistics(periods: 47, meanError: 0.215, ratio: 0.999974, frames: 196)),
        ])
    }

    func testALineIsUnderstoodOnceItIsComplete() {
        var parser = LinkLogParser()
        XCTAssertEqual(parser.feed(Data("Receiv".utf8)), [])
        XCTAssertEqual(parser.feed(Data("ing.\r".utf8)), [])
        XCTAssertEqual(parser.feed(Data("\nSyncing...\n".utf8)), [.receiving, .syncing])
    }

    func testTheSenderMayBeAnIPv6Address() {
        XCTAssertEqual(events("From fe80::1c3:a2ff:fe10:5%en7 : 8 chan, 44100 Hz\n"),
                       [.senderFound(address: "fe80::1c3:a2ff:fe10:5%en7", channels: 8, rate: 44100)])
    }

    func testTheReceiverWaitsAndStartsAgain() {
        XCTAssertEqual(events("Waiting for  5.0 seconds...\n"), [.retrying(seconds: 5.0)])
        XCTAssertEqual(events("Waiting for 10.0 seconds...\n"), [.retrying(seconds: 10.0)])
        XCTAssertEqual(events("Transmitter terminated.\n"), [.transmitterEnded])
        XCTAssertEqual(events("Fatal error, terminating.\n"), [.fatal])
        XCTAssertEqual(events("Fatal error condition, terminating.\n"), [.fatal], "the sender says it a little differently")
    }

    func testAQueueThatRunsDryShowsAsZeroOrLess() throws {
        guard case .statistics(let s)? = events(" 47   -3.250  0.999100      -12\n").first else { return XCTFail("not read as statistics") }
        XCTAssertEqual(s.frames, -12)
        XCTAssertLessThan(s.margin(senderRate: 48000), 0)
    }

    func testTheMarginIsInMillisecondsAtTheRateOfTheSender() {
        let s = LinkStatistics(periods: 48, meanError: 0, ratio: 1, frames: 960)
        XCTAssertEqual(s.margin(senderRate: 48000), 20, accuracy: 1e-9)
        XCTAssertEqual(s.margin(senderRate: 96000), 10, accuracy: 1e-9)
        XCTAssertEqual(s.margin(senderRate: 0), 0, "no rate known yet")
    }

    func testTheRatioIsGivenInPartsPerMillion() {
        let s = LinkStatistics(periods: 1, meanError: 0, ratio: 1.000040, frames: 0)
        XCTAssertEqual(s.ratioOffsetPPM, 40, accuracy: 1e-6)
    }

    func testWhatMakesTheProgramImpossibleToRunIsAnError() {
        for line in ["Can't connect to Jack, is the server running ?", "Address resolution failed.", "Failed to open socket.",
                     "Port number is out of range.", "Buffer time is out of range.", "Format error in channel list",
                     "Number of channels is out of range.", "Multicast requires a network device.", "Bad option argument: --chan x"] {
            XCTAssertEqual(events(line + "\n"), [.error(line)], line)
        }
    }

    func testWarningsAreNotErrors() {
        XCTAssertEqual(events("Ignored extra argument 'en7'.\n"), [.warning("Ignored extra argument 'en7'.")])
        XCTAssertEqual(events("Warning: memory lock failed.\n"), [.warning("Warning: memory lock failed.")])
    }

    func testAnythingElseIsAMessage() {
        XCTAssertEqual(events("something new\n"), [.message("something new")])
        XCTAssertEqual(events("\n\r\n   \n"), [], "blank lines say nothing")
    }

    func testALineThatNeverEndsDoesNotGrowWithoutLimit() {
        var parser = LinkLogParser()
        _ = parser.feed(Data(repeating: 0x41, count: 70_000))
        XCTAssertEqual(parser.feed(Data("Syncing...\n".utf8)), [.syncing], "the parser recovered")
    }
}
