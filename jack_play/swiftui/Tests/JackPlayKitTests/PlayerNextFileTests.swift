// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import JackPlayKit

/// The next file of a playlist: a second program is started for it, paused, while the first one plays, and takes over at the end.
@MainActor
final class PlayerNextFileTests: XCTestCase {
    private var files: TestFiles!
    private var defaults: UserDefaults!
    private var runners: [FakeRunner] = []

    override func setUp() async throws {
        files = try TestFiles()
        let name = "jackplay-next-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: name)
        addTeardownBlock { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        runners = []
    }

    private func make(mode: PlayerCommand.Mode = .independent, settings: PlayerSettings = PlayerSettings()) -> (PlayerModel, FakeServer) {
        let server = FakeServer()
        let model = PlayerModel(server: server, store: ConnectionStore(defaults: defaults), settings: settings, mode: mode) { [unowned self] command in
            let r = FakeRunner(command: command)
            self.runners.append(r)
            return r
        }
        return (model, server)
    }

    private func file(_ channels: Int = 2, frames: Int = 48000 * 4) throws -> URL {
        try files.write(TestFiles.all[0], channels: channels, frames: frames)
    }

    /// A model that plays a file, with a next one chosen: the program of the first is ready.
    private func playing() throws -> (PlayerModel, FakeServer, URL, URL) {
        let (model, server) = make()
        let a = try file(), b = try file()
        model.open(a)
        runners[0].ready()
        model.nextFile = b
        return (model, server, a, b)
    }

    func testTheNextProgramStartsPausedUnderAnotherName() throws {
        let (_, _, _, b) = try playing()
        XCTAssertEqual(runners.count, 2)
        XCTAssertEqual(runners[1].command.file, b)
        XCTAssertEqual(runners[1].command.settings.clientName, "02 - jack_play", "it lives beside the first one: its own name")
        XCTAssertEqual(runners[0].command.settings.clientName, "jack_play")
        XCTAssertTrue(runners[1].started)
        XCTAssertTrue(runners[1].controls.isEmpty, "it waits")
    }

    func testItsPortsAreConnectedWhileItWaits() throws {
        let (model, server, _, _) = try playing()
        XCTAssertFalse(model.nextIsReady)
        runners[1].ready()
        XCTAssertTrue(model.nextIsReady)
        XCTAssertTrue(server.links.contains("02 - jack_play:out_1>system:playback_1"))
        XCTAssertTrue(server.links.contains("02 - jack_play:out_2>system:playback_2"))
    }

    func testTheNextFileTakesOverAndPlays() throws {
        let (model, _, _, b) = try playing()
        runners[1].ready()
        XCTAssertTrue(model.advanceToNext(play: true))
        XCTAssertEqual(model.file?.url, b)
        XCTAssertEqual(model.position, 0)
        XCTAssertEqual(model.phase, .running(.paused))
        XCTAssertTrue(runners[0].stopped, "the first program leaves")
        XCTAssertEqual(runners[1].controls, [.play])
        // The new program is the player: what it says is taken.
        runners[1].say(.position(frame: 100, state: .playing))
        XCTAssertEqual(model.position, 100)
        XCTAssertEqual(model.phase, .running(.playing))
    }

    func testWithoutPlayTheNextFileOnlyArrives() throws {
        let (model, _, _, _) = try playing()
        runners[1].ready()
        XCTAssertTrue(model.advanceToNext(play: false))
        XCTAssertTrue(runners[1].controls.isEmpty)
    }

    func testANextProgramThatIsNotReadyCannotTakeOver() throws {
        let (model, _, a, _) = try playing()
        XCTAssertFalse(model.advanceToNext(play: true))
        XCTAssertEqual(model.file?.url, a)
        XCTAssertTrue(runners[0].controls.isEmpty)
    }

    func testTheNamesFollowThePlaceInThePlaylist() throws {
        let (model, _) = make()
        model.currentNumber = 1
        model.nextNumber = 2
        model.open(try file())
        runners[0].ready()
        model.nextFile = try file()
        XCTAssertEqual(runners[0].command.settings.clientName, "01 - jack_play")
        XCTAssertEqual(runners[1].command.settings.clientName, "02 - jack_play")
        runners[1].ready()
        runners[0].say(.position(frame: 100, state: .playing))
        runners[0].say(.endAnnounced(5000))
        XCTAssertTrue(model.advanceToNext(play: true))
        XCTAssertEqual(model.currentNumber, 2)
        model.nextNumber = 3
        model.nextFile = try file()
        XCTAssertEqual(runners[2].command.settings.clientName, "03 - jack_play", "nothing is renamed: the next one has the next number")
    }

    func testWhenTheListGoesRoundTheNameIsFreeOnlyOnceTheOldProgramHasLeft() throws {
        let (model, _) = make()
        let a = try file(), b = try file()
        model.currentNumber = 1
        model.nextNumber = 2
        model.open(a)
        runners[0].ready()
        model.nextFile = b
        runners[1].ready()
        runners[0].leavesAtOnce = false
        runners[0].say(.position(frame: 100, state: .playing))
        runners[0].say(.endAnnounced(5000))
        XCTAssertTrue(model.advanceToNext(play: true))   // file 02 plays, file 01 is leaving, slowly
        model.nextNumber = 1                              // the list goes round: file 01 again
        model.nextFile = a
        XCTAssertEqual(runners.count, 2, "its name is still taken by the program that leaves")
        runners[0].leave()
        XCTAssertEqual(runners.count, 3)
        XCTAssertEqual(runners[2].command.settings.clientName, "01 - jack_play")
    }

    func testAnotherNumberForTheNextFileMakesAnotherProgram() throws {
        let (model, _) = make()
        model.currentNumber = 1
        model.nextNumber = 2
        model.open(try file())
        runners[0].ready()
        model.nextFile = try file()
        model.nextNumber = 3      // a file was inserted before it
        XCTAssertTrue(runners[1].stopped)
        XCTAssertEqual(runners[2].command.settings.clientName, "03 - jack_play")
    }

    func testWithoutNumbersTheTwoProgramsStillHaveTwoNames() throws {
        let (model, _) = make()
        model.open(try file())
        runners[0].ready()
        model.nextFile = try file()
        XCTAssertEqual(runners[0].command.settings.clientName, "jack_play")
        XCTAssertEqual(runners[1].command.settings.clientName, "02 - jack_play")
    }

    func testTheEndOfTheFileIsReportedOnce() throws {
        let (model, _, _, _) = try playing()
        var ended = 0
        model.onFileEnded = { ended += 1 }
        runners[0].say(.position(frame: 190_000, state: .playing))
        runners[0].say(.position(frame: 192_000, state: .ended))
        runners[0].say(.position(frame: 192_000, state: .ended))
        XCTAssertEqual(ended, 1)
        model.seek(frame: 0)
        runners[0].say(.position(frame: 0, state: .paused))
        runners[0].say(.position(frame: 192_000, state: .ended))
        XCTAssertEqual(ended, 2, "played again to the end")
    }

    func testNoNextFileMeansNoSecondProgram() throws {
        let (model, _, _, _) = try playing()
        model.nextFile = nil
        XCTAssertTrue(runners[1].stopped)
        XCTAssertFalse(model.nextIsReady)
    }

    func testChangingTheNextFileReplacesTheProgram() throws {
        let (model, _, _, _) = try playing()
        let c = try file()
        model.nextFile = c
        XCTAssertTrue(runners[1].stopped)
        XCTAssertEqual(runners.count, 3)
        XCTAssertEqual(runners[2].command.file, c)
        XCTAssertEqual(runners[2].command.settings.clientName, "02 - jack_play")
    }

    func testChangingASettingStartsEverythingAgain() throws {
        let (model, _, _, b) = try playing()
        runners[1].ready()
        model.update(settings: PlayerSettings(converter: 2))
        XCTAssertTrue(runners[1].stopped)
        runners[2].ready()   // the first program again, with its new options
        XCTAssertEqual(runners.count, 4, "and the next one again")
        XCTAssertEqual(runners[3].command.file, b)
        XCTAssertTrue(runners[3].command.arguments.contains("2"))
    }

    func testLoopingTheFileNeedsNoNextProgram() throws {
        let (model, _, _, _) = try playing()
        model.update(settings: PlayerSettings(loop: true))
        XCTAssertTrue(runners[1].stopped)
        runners[2].ready()
        XCTAssertEqual(runners.count, 3, "the program loops by itself")
    }

    func testFollowingTheTransportStartsNothingInAdvance() throws {
        let (model, _) = make(mode: .followTransport)
        model.open(try file())
        runners[0].ready()
        model.nextFile = try file()
        XCTAssertEqual(runners.count, 1)
    }

    func testClosingTheFileStopsTheNextProgramToo() throws {
        let (model, _, _, _) = try playing()
        model.closeFile()
        XCTAssertTrue(runners[1].stopped)
    }

    // MARK: Starting at the end, to the frame

    func testTheNextProgramIsToldWhenTheFileEnds() throws {
        let (model, _, _, _) = try playing()
        runners[1].ready()
        runners[0].say(.position(frame: 100, state: .playing))
        runners[0].say(.endAnnounced(123_456_789))
        XCTAssertEqual(runners[1].controls, [.playAt(123_456_789)])
        XCTAssertTrue(model.nextIsReady)
        // Said again (the program may say it twice): once is enough.
        runners[0].say(.endAnnounced(123_456_789))
        XCTAssertEqual(runners[1].controls.count, 1)
    }

    func testNothingIsSentToAProgramThatIsNotReady() throws {
        let (_, _, _, _) = try playing()
        runners[0].say(.position(frame: 100, state: .playing))
        runners[0].say(.endAnnounced(1000))
        XCTAssertTrue(runners[1].controls.isEmpty, "it is still starting: the usual start, at the end of the file, will do")
    }

    func testTheNextProgramTakesOverWithoutAPlayWhenItWasTold() throws {
        let (model, _, _, b) = try playing()
        runners[1].ready()
        runners[0].say(.position(frame: 100, state: .playing))
        runners[0].say(.endAnnounced(5000))
        XCTAssertTrue(model.advanceToNext(play: true))
        XCTAssertEqual(model.file?.url, b)
        XCTAssertEqual(runners[1].controls, [.playAt(5000)], "no second order: it starts by itself")
        XCTAssertEqual(model.phase, .running(.playing))
    }

    func testAPauseCancelsTheStartAtTheEnd() throws {
        let (model, _, _, _) = try playing()
        runners[1].ready()
        runners[0].say(.position(frame: 100, state: .playing))
        runners[0].say(.endAnnounced(5000))
        model.pause()
        XCTAssertEqual(runners[1].controls, [.playAt(5000), .pause], "the next one waits again")
        XCTAssertEqual(runners[0].controls.last, .pause)
        // The program says the end again after it plays on, with the new time.
        runners[0].say(.position(frame: 100, state: .playing))
        runners[0].say(.endAnnounced(9000))
        XCTAssertEqual(runners[1].controls.last, .playAt(9000))
    }

    func testASeekCancelsTheStartAtTheEnd() throws {
        let (model, _, _, _) = try playing()
        runners[1].ready()
        runners[0].say(.position(frame: 100, state: .playing))
        runners[0].say(.endAnnounced(5000))
        model.seek(frame: 10)
        XCTAssertEqual(runners[1].controls, [.playAt(5000), .pause])
    }

    func testTheEndIsNotSaidWhenThereIsNoNextFile() throws {
        let (model, _, _, _) = try playing()
        model.nextFile = nil
        runners[0].say(.position(frame: 100, state: .playing))
        runners[0].say(.endAnnounced(5000))
        XCTAssertTrue(runners[1].controls.isEmpty)
    }
}
