// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import JackPlayKit

/// The rules of the order of a playlist, and the playlist file.
final class PlaylistTests: XCTestCase {
    private func u(_ n: String) -> URL { URL(fileURLWithPath: "/m/\(n).wav") }
    private func list(_ names: String..., current: Int? = nil, mode: RepeatMode = .off) -> Playlist {
        Playlist(items: names.map(u), current: current, repeatMode: mode)
    }

    func testTheNextFileFollowsTheOrderAndTheListEndsOrGoesRound() {
        XCTAssertEqual(list("a", "b", "c", current: 0).nextIndex, 1)
        XCTAssertNil(list("a", "b", "c", current: 2).nextIndex, "the list ends")
        XCTAssertEqual(list("a", "b", "c", current: 2, mode: .list).nextIndex, 0, "the list goes round")
        XCTAssertNil(list("a", "b", "c", current: 1, mode: .file).nextIndex, "the same file plays again by itself")
        XCTAssertEqual(list("a", "b", current: nil).nextIndex, 0)
        XCTAssertNil(Playlist().nextIndex)
    }

    func testAListOfOneFileThatRepeatsLoopsTheFileInsteadOfMakingASecondProgram() {
        let one = list("a", current: 0, mode: .list)
        XCTAssertNil(one.nextIndex)
        XCTAssertTrue(one.loopsTheFile)
        XCTAssertFalse(list("a", "b", current: 0, mode: .list).loopsTheFile)
        XCTAssertTrue(list("a", "b", current: 0, mode: .file).loopsTheFile)
    }

    func testThePreviousFile() {
        XCTAssertEqual(list("a", "b", current: 1).previousIndex, 0)
        XCTAssertNil(list("a", "b", current: 0).previousIndex)
        XCTAssertEqual(list("a", "b", "c", current: 0, mode: .list).previousIndex, 2)
    }

    func testInsertingBeforeTheCurrentFileKeepsItCurrent() {
        var p = list("a", "b", "c", current: 1)
        p.insert([u("x"), u("y")], at: 0)
        XCTAssertEqual(p.current, 3)
        XCTAssertEqual(p.items[p.current!], u("b"))
        p.insert([u("z")], at: 5)
        XCTAssertEqual(p.items[p.current!], u("b"))
    }

    func testRemovingFiles() {
        var p = list("a", "b", "c", "d", current: 2)
        p.remove(at: [0, 3])
        XCTAssertEqual(p.items, [u("b"), u("c")])
        XCTAssertEqual(p.current, 1)
        p.remove(at: [1])
        XCTAssertNil(p.current, "the file that plays is no longer in the list")
    }

    func testMovingFilesFollowsTheCurrentOne() {
        var p = list("a", "b", "c", "d", current: 1)
        p.move(from: [3], to: 0)                    // d goes first
        XCTAssertEqual(p.items, ["d", "a", "b", "c"].map(u))
        XCTAssertEqual(p.items[p.current!], u("b"))
        p.move(from: [2], to: 4)                    // the current one goes last
        XCTAssertEqual(p.items, ["d", "a", "c", "b"].map(u))
        XCTAssertEqual(p.current, 3)
        p.move(from: [0, 1], to: 4)                 // two files at once
        XCTAssertEqual(p.items, ["c", "b", "d", "a"].map(u))
        XCTAssertEqual(p.items[p.current!], u("b"))
    }

    func testTheSameFileTwiceInTheListIsFollowedByItsPlace() {
        var p = Playlist(items: [u("a"), u("b"), u("a")], current: 2)
        p.move(from: [0], to: 3)
        XCTAssertEqual(p.items, ["b", "a", "a"].map(u))
        XCTAssertEqual(p.current, 1, "the place of the second a")
    }

    func testPlaylistFileRoundTrip() {
        let folder = URL(fileURLWithPath: "/Users/x/Music/Show", isDirectory: true)
        let urls = [folder.appendingPathComponent("01 intro.wav"), folder.appendingPathComponent("sub/02 é.flac"), URL(fileURLWithPath: "/Volumes/Disk/other.wav")]
        let text = M3U.text(for: urls, folder: folder)
        XCTAssertEqual(text, "#EXTM3U\n01 intro.wav\nsub/02 é.flac\n/Volumes/Disk/other.wav\n")
        XCTAssertEqual(M3U.parse(text, folder: folder), urls)
    }

    func testReadingPlaylistFilesOfOtherPlayers() {
        let folder = URL(fileURLWithPath: "/Users/x/Music", isDirectory: true)
        let text = "\u{FEFF}#EXTM3U\r\n#EXTINF:123,Artist - Title\r\nSong one.mp3\r\n\r\n   \r\n/abs/two.ogg\r\nfile:///Users/y/three%20x.wav\r\n# a comment\r\n../up.wav\r\n"
        XCTAssertEqual(M3U.parse(text, folder: folder).map(\.path),
                       ["/Users/x/Music/Song one.mp3", "/abs/two.ogg", "/Users/y/three x.wav", "/Users/x/up.wav"])
    }
}
