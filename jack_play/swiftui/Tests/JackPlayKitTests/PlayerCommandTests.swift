// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import JackPlayKit

final class PlayerCommandTests: XCTestCase {
    private let file = URL(fileURLWithPath: "/Users/x/Music/Intro.wav")

    func testTheDefaultCommandPutsTheProgramUnderControl() {
        XCTAssertEqual(PlayerCommand(file: file).arguments,
                       ["-C", "-u", "-n", "jack_play", "-c", "0", "-b", "4096", "/Users/x/Music/Intro.wav"])
    }

    func testTheSettingsBecomeOptions() {
        let c = PlayerCommand(file: file, settings: PlayerSettings(converter: 2, bufferFrames: 16384, clientName: "lecteur", loop: true))
        XCTAssertEqual(c.arguments, ["-C", "-u", "-n", "lecteur", "-c", "2", "-b", "16384", "-l", "/Users/x/Music/Intro.wav"])
    }

    func testFollowingTheTransportWatchesInsteadOfControlling() {
        let c = PlayerCommand(file: file, settings: PlayerSettings(loop: true), mode: .followTransport)
        XCTAssertEqual(c.arguments, ["-t", "-u", "-n", "jack_play", "-c", "0", "-b", "4096", "-M", "/Users/x/Music/Intro.wav"])
        XCTAssertFalse(c.arguments.contains("-C"), "-C and -t cannot go together")
        XCTAssertFalse(c.arguments.contains("-l"), "the program does not loop when it follows the transport")
        XCTAssertTrue(c.display().hasPrefix("jack_play -t "))
    }

    func testTheStartPositionIsGivenInFramesOfTheFile() {
        XCTAssertTrue(PlayerCommand(file: file, initialFrame: 96000).arguments.contains("96000"))
        XCTAssertFalse(PlayerCommand(file: file, initialFrame: 0).arguments.contains("-i"))
        XCTAssertFalse(PlayerCommand(file: file, initialFrame: nil).arguments.contains("-i"))
    }

    func testAFileNameThatLooksLikeAnOptionStaysAPath() {
        // A file URL is always an absolute path, so "-l.wav" becomes "/…/-l.wav", which no option parser takes for an option.
        let last = PlayerCommand(file: URL(fileURLWithPath: "-l.wav")).arguments.last!
        XCTAssertTrue(last.hasPrefix("/"))
        XCTAssertTrue(last.hasSuffix("/-l.wav"))
    }

    func testTheCommandLineIsWhatAPersonWouldType() {
        XCTAssertEqual(PlayerCommand(file: file).display(),
                       "jack_play -C -u -n jack_play -c 0 -b 4096 /Users/x/Music/Intro.wav")

    func testTheBufferIsAtLeastFourPeriodsOfTheServer() {
        // The program stops with "period size exceeds limit" when its buffer is not larger than a period.
        XCTAssertEqual(PlayerCommand(file: file, settings: PlayerSettings(bufferFrames: 1024), serverPeriod: 2048).bufferFrames, 8192)
        XCTAssertEqual(PlayerCommand(file: file, settings: PlayerSettings(bufferFrames: 16384), serverPeriod: 2048).bufferFrames, 16384)
        XCTAssertEqual(PlayerCommand(file: file, settings: PlayerSettings(bufferFrames: 2048)).bufferFrames, 2048)
        XCTAssertTrue(PlayerCommand(file: file, settings: PlayerSettings(bufferFrames: 1024), serverPeriod: 2048).arguments.contains("8192"))
    }

    func testTheBufferHoldsAtLeastATenthOfASecondOfTheFile() {
        // At 192 kHz, 4096 frames are 21 ms: too little to tell the next program in time.
        XCTAssertEqual(PlayerCommand(file: file, fileRate: 192_000).bufferFrames, 19_200)
        XCTAssertEqual(PlayerCommand(file: file, fileRate: 44_100).bufferFrames, 4096, "the usual size is enough")
        XCTAssertEqual(PlayerCommand(file: file, settings: PlayerSettings(bufferFrames: 32768), fileRate: 192_000).bufferFrames, 32768)
    }

    func testTheProgramIsNamedForItsPlaceInThePlaylist() {
        let settings = PlayerSettings(clientName: "jack_play")
        XCTAssertEqual(settings.programName(number: nil), "jack_play")
        XCTAssertEqual(settings.programName(number: 2), "02 - jack_play")
        XCTAssertEqual(settings.programName(number: 12), "12 - jack_play")
        XCTAssertEqual(settings.programName(number: 2, of: 12), "02 of 12 - jack_play")
        XCTAssertEqual(settings.programName(number: 123), "123 - jack_play")
        XCTAssertTrue(PlayerCommand(file: file, settings: PlayerSettings(clientName: settings.programName(number: 2))).arguments.contains("02 - jack_play"),
                      "a name with spaces is one argument")
        // Whatever the name chosen, two places differ within the first characters (JACK keeps 31 of "js<uid>.<server><client>").
        let long = PlayerSettings(clientName: String(repeating: "x", count: 100))
        for (number, other) in [(1, 2), (9, 10), (99, 100)] {
            let a = long.programName(number: number, of: 100), b = long.programName(number: other, of: 100)
            XCTAssertLessThan(zip(a, b).prefix { $0 == $1 }.count, 8)
            XCTAssertLessThanOrEqual(a.count, 63, "JACK names are 63 characters at most")
        }
    }

    func testTheProgramSaysWhenTheFileWillEnd() {
        var parser = PlayerLogParser()
        XCTAssertEqual(parser.feed(Data("end 4294967000\nend nonsense\n".utf8)), [.endAnnounced(4_294_967_000), .message("end nonsense")])
        XCTAssertEqual(PlayerControl.playAt(123).line, "play at 123")
        XCTAssertEqual(PlayerControl.levels(false).line, "levels off")
        XCTAssertEqual(PlayerControl.levels(true).line, "levels on")
    }

    func testTheProgramSaysTheNameOfItsClient() {
        var parser = PlayerLogParser()
        XCTAssertEqual(parser.feed(Data("client Salle A-01\nready 2 48000 48000 10\n".utf8)),
                       [.client("Salle A-01"), .ready(channels: 2, fileRate: 48000, serverRate: 48000, frames: 10)])
    }
    }

    func testTheCommandLineQuotesWhatNeedsIt() {
        let c = PlayerCommand(file: URL(fileURLWithPath: "/Users/x/Ma musique/L'été (1).wav"))
        XCTAssertEqual(c.display().components(separatedBy: " -b 4096 ").last, "'/Users/x/Ma musique/L'\\''été (1).wav'")
        XCTAssertEqual(PlayerCommand.quote(""), "''")
        XCTAssertEqual(PlayerCommand.quote("plain-name_1.wav"), "plain-name_1.wav")
        XCTAssertEqual(PlayerCommand.quote("a b"), "'a b'")
    }

    func testAClientNameJackAcceptsIsKept() {
        XCTAssertEqual(PlayerSettings(clientName: "jack_play").safeClientName, "jack_play")
        XCTAssertEqual(PlayerSettings(clientName: "salle:A/1").safeClientName, "salle_A_1")
        XCTAssertEqual(PlayerSettings(clientName: "   ").safeClientName, "jack_play")
        XCTAssertEqual(PlayerSettings(clientName: "").safeClientName, "jack_play")
        XCTAssertEqual(PlayerSettings(clientName: String(repeating: "x", count: 100)).safeClientName.count, 48)
    }

    func testTheControlsAreOneLineEach() {
        XCTAssertEqual(PlayerControl.play.line, "play")
        XCTAssertEqual(PlayerControl.pause.line, "pause")
        XCTAssertEqual(PlayerControl.seek(96000).line, "seek 96000")
        XCTAssertEqual(PlayerControl.seek(-5).line, "seek 0")
        XCTAssertEqual(PlayerControl.quit.line, "quit")
    }
}

final class PlayerLogParserTests: XCTestCase {
    func testTheReadyLine() {
        var parser = PlayerLogParser()
        XCTAssertEqual(parser.feed(Data("ready 6 44100 48000 5292000\n".utf8)),
                       [.ready(channels: 6, fileRate: 44100, serverRate: 48000, frames: 5_292_000)])
    }

    func testThePositionLinesWithTheirStates() {
        var parser = PlayerLogParser()
        let events = parser.feed(Data("pos 0 paused\npos 96000 playing\npos 192000 ended\n".utf8))
        XCTAssertEqual(events, [.position(frame: 0, state: .paused), .position(frame: 96000, state: .playing), .position(frame: 192000, state: .ended)])
    }

    func testAFrameBeyondThirtyTwoBitsIsKept() {
        var parser = PlayerLogParser()
        XCTAssertEqual(parser.feed(Data("pos 5000000000 playing\n".utf8)), [.position(frame: 5_000_000_000, state: .playing)])
    }

    func testALineArrivesInPieces() {
        var parser = PlayerLogParser()
        XCTAssertTrue(parser.feed(Data("pos 12".utf8)).isEmpty)
        XCTAssertTrue(parser.feed(Data("34 play".utf8)).isEmpty)
        XCTAssertEqual(parser.feed(Data("ing\npos 5 paused\n".utf8)), [.position(frame: 1234, state: .playing), .position(frame: 5, state: .paused)])
    }

    func testOtherLinesAreInformationAndEmptyOnesAreDropped() {
        var parser = PlayerLogParser()
        XCTAssertEqual(parser.feed(Data("jack client name: jack_play\n\n  \nrju-play: resampling, 44100 != 48000 (1.08844)\n".utf8)),
                       [.message("jack client name: jack_play"), .message("rju-play: resampling, 44100 != 48000 (1.08844)")])
    }

    func testMalformedLinesAreInformationToo() {
        var parser = PlayerLogParser()
        let events = parser.feed(Data("pos abc playing\nready 2 48000\npos 10 sideways\n".utf8))
        XCTAssertEqual(events.count, 3)
        for event in events { guard case .message = event else { return XCTFail("\(event)") } }
    }

    func testTheLevelsOfEveryChannel() {
        var parser = PlayerLogParser()
        XCTAssertEqual(parser.feed(Data("lev 0.4981 0.2490\n".utf8)), [.levels([0.4981, 0.2490])])
        XCTAssertEqual(parser.feed(Data("lev 0.0000\n".utf8)), [.levels([0])])
        let many = (0..<64).map { String(format: "%.4f", Double($0) / 100) }.joined(separator: " ")
        guard case .levels(let values)? = parser.feed(Data("lev \(many)\n".utf8)).first else { return XCTFail("64 channels") }
        XCTAssertEqual(values.count, 64)
        XCTAssertEqual(values[63], 0.63, accuracy: 1e-6)
    }

    func testALevelLineThatIsNotUnderstoodIsInformation() {
        var parser = PlayerLogParser()
        for line in ["lev", "lev abc", "lev 0.5 nan", "lev 0.5 -1", "lev 0.5 inf"] {
            guard case .message? = parser.feed(Data((line + "\n").utf8)).first else { return XCTFail(line) }
        }
    }

    func testTheStandardErrorIsWarnings() {
        var parser = PlayerLogParser(isError: true)
        XCTAssertEqual(parser.feed(Data("rju-play: disk thread late (12 < 1024)\n".utf8)), [.warning("rju-play: disk thread late (12 < 1024)")])
    }

    func testALineThatNeverEndsDoesNotGrowForever() {
        var parser = PlayerLogParser()
        for _ in 0..<100 { _ = parser.feed(Data(repeating: 0x61, count: 2000)) }
        XCTAssertEqual(parser.feed(Data("pos 1 paused\n".utf8)).count, 1)
    }
}
