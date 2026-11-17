// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import JackPlayKit

/// The playlist with the player (and fake programs): who is open, who is next, what happens at the end of a file.
@MainActor
final class PlaylistModelTests: XCTestCase {
    private var files: TestFiles!
    private var defaults: UserDefaults!
    private var runners: [FakeRunner] = []

    override func setUp() async throws {
        files = try TestFiles()
        let name = "jackplay-list-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: name)
        addTeardownBlock { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        runners = []
    }

    private func make() -> (PlaylistModel, PlayerModel) {
        let player = PlayerModel(server: FakeServer(), store: ConnectionStore(defaults: defaults)) { [unowned self] command in
            let r = FakeRunner(command: command)
            self.runners.append(r)
            return r
        }
        return (PlaylistModel(player: player), player)
    }

    private func urls(_ n: Int) throws -> [URL] {
        try (0..<n).map { _ in try files.write(TestFiles.all[0], channels: 2, frames: 48000 * 4) }
    }

    func testANewListOpensItsFirstFileAndPreparesTheSecond() throws {
        let (list, player) = make()
        let u = try urls(3)
        list.replace(with: u)
        XCTAssertEqual(player.file?.url, u[0])
        XCTAssertEqual(runners[0].command.settings.clientName, "01 of 03 - jack_play")
        runners[0].ready()
        XCTAssertEqual(player.nextFile, u[1])
        XCTAssertEqual(runners.last?.command.file, u[1])
        XCTAssertEqual(runners.last?.command.settings.clientName, "02 of 03 - jack_play")
        XCTAssertTrue(list.hasNext)
        XCTAssertFalse(list.hasPrevious)
    }

    func testOneFileHasNoNumberAndNoNextProgram() throws {
        let (list, player) = make()
        list.replace(with: try urls(1))
        runners[0].ready()
        XCTAssertEqual(runners[0].command.settings.clientName, "jack_play")
        XCTAssertNil(player.nextFile)
        XCTAssertEqual(runners.count, 1)
    }

    func testAtTheEndOfAFileTheNextOneTakesOver() throws {
        let (list, player) = make()
        let u = try urls(3)
        list.replace(with: u, play: true)
        runners[0].ready()
        runners[1].ready()
        runners[0].say(.position(frame: 190_000, state: .playing))
        runners[0].say(.position(frame: 192_000, state: .ended))
        XCTAssertEqual(player.file?.url, u[1])
        XCTAssertEqual(list.playlist.current, 1)
        XCTAssertEqual(player.nextFile, u[2], "the one after is prepared")
        XCTAssertEqual(player.currentNumber, 2)
    }

    func testTheLastFileEndsTheListUnlessItRepeats() throws {
        let (list, player) = make()
        let u = try urls(2)
        list.replace(with: u, play: true)
        runners[0].ready(); runners[1].ready()
        runners[0].say(.position(frame: 192_000, state: .ended))
        XCTAssertEqual(list.playlist.current, 1)
        runners.last { $0.started && !$0.stopped }?.say(.position(frame: 192_000, state: .ended))
        XCTAssertEqual(list.playlist.current, 1, "the list ends")
        XCTAssertFalse(list.hasNext)
        list.setRepeat(.list)
        XCTAssertTrue(list.hasNext)
        XCTAssertEqual(player.nextFile, u[0], "it goes round")
    }

    func testTheFileModeLoopsInsideTheProgram() throws {
        let (list, player) = make()
        list.replace(with: try urls(3))
        runners[0].ready()
        list.setRepeat(.file)
        XCTAssertTrue(player.settings.loop)
        XCTAssertNil(player.nextFile)
        list.setRepeat(.off)
        XCTAssertFalse(player.settings.loop)
    }

    func testAListOfOneFileThatRepeatsLoopsTheFile() throws {
        let (list, player) = make()
        list.setRepeat(.list)
        list.replace(with: try urls(1))
        XCTAssertTrue(player.settings.loop)
        list.append(try urls(1))
        XCTAssertFalse(player.settings.loop, "two files: the list repeats, not the file")
    }

    func testNextAndPreviousByTheButtons() throws {
        let (list, player) = make()
        let u = try urls(3)
        list.replace(with: u)
        runners[0].ready(); runners[1].ready()
        list.next()
        XCTAssertEqual(player.file?.url, u[1])
        XCTAssertEqual(list.playlist.current, 1)
        list.previous()   // at the start of file 2 (position 0): the file before
        XCTAssertEqual(player.file?.url, u[0])
        XCTAssertEqual(list.playlist.current, 0)
    }

    func testFilesThatCannotBePlayedAreSkipped() throws {
        let (list, _) = make()
        let u = try urls(3)
        list.isPlayable = { $0 != u[1] }
        list.replace(with: u)
        XCTAssertEqual(list.nextFile, u[2])
    }

    func testRestoringTheListOpensTheCurrentFileWithoutPlaying() throws {
        let (list, player) = make()
        let u = try urls(3)
        list.restore(items: u, current: 1, repeatMode: .list)
        XCTAssertEqual(player.file?.url, u[1])
        XCTAssertEqual(list.repeatMode, .list)
        runners[0].ready()
        XCTAssertEqual(player.phase, .running(.paused))
        XCTAssertTrue(runners[0].controls.isEmpty)
    }

    func testTheListKnowsWhereEachFileGoes() throws {
        let (list, player) = make()
        let u = try urls(2)
        list.replace(with: u)
        runners[0].ready()
        // The file that is open: the routing in use. The other one: what it gets the first time.
        XCTAssertEqual(player.routing(for: u[0], channels: 2).connectedChannels, 2)
        XCTAssertEqual(player.routing(for: u[1], channels: 2), DefaultRouting.make(channels: 2, playbackPorts: ["system:playback_1", "system:playback_2"]))
        player.setRouting(ChannelRouting(channels: [["Carla:in1"], []]))
        XCTAssertEqual(player.routing(for: u[0], channels: 2).connectedChannels, 1)
    }

    func testTheApplicationIsToldAboutChanges() throws {
        let (list, _) = make()
        var changes = 0
        list.onChange = { changes += 1 }
        list.replace(with: try urls(2))
        list.setRepeat(.list)
        list.remove(at: [1])
        XCTAssertGreaterThanOrEqual(changes, 3)
    }
}
