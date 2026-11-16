// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import JackPlayKit

/// A stand-in for jack_play, in shell: it answers the same lines, so that the process handling is tested without a
/// JACK server. FAKE_MODE changes what it does.
private let fakeProgram = """
#!/bin/sh
echo "jack client name: fake"
case "$FAKE_MODE" in
  crash) echo "ready 2 48000 48000 192000"; echo "something went wrong" 1>&2; exit 3;;
esac
echo "ready 2 48000 48000 192000"
echo "pos 0 paused"
while read line; do
  case "$line" in
    play) echo "pos 100 playing";;
    pause) echo "pos 100 paused";;
    seek*) echo "pos ${line#seek } paused";;
    quit) if [ "$FAKE_MODE" = deaf ]; then sleep 30; else exit 0; fi;;
  esac
done
echo "input closed" 1>&2
exit 0
"""

@MainActor
final class PlayerProcessTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("jackplay-process-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws { try? FileManager.default.removeItem(at: directory) }

    private func makeFake() throws -> URL {
        let url = directory.appendingPathComponent("fake_jack_play")
        try fakeProgram.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    private func makeProcess(mode: String? = nil) throws -> (PlayerProcess, Box) {
        var environment = ProcessInfo.processInfo.environment
        environment["FAKE_MODE"] = mode ?? ""
        let process = PlayerProcess(executable: try makeFake(), command: PlayerCommand(file: URL(fileURLWithPath: "/tmp/x.wav")), environment: environment)
        let box = Box()
        process.onEvent = { box.events.append($0) }
        return (process, box)
    }

    final class Box { var events = [PlayerEvent]() }

    private func wait(_ box: Box, timeout: TimeInterval = 5, for condition: @escaping ([PlayerEvent]) -> Bool) async {
        let end = Date().addingTimeInterval(timeout)
        while !condition(box.events), Date() < end { try? await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertTrue(condition(box.events), "events: \(box.events)")
    }

    private func hasExit(_ e: [PlayerEvent]) -> Bool { e.contains { if case .exited = $0 { return true }; return false } }

    func testTheProgramIsReadyAndAnswersCommands() async throws {
        let (process, box) = try makeProcess()
        try process.start()
        XCTAssertTrue(process.isRunning)
        XCTAssertNotNil(process.processIdentifier)
        XCTAssertEqual(process.clientName, "jack_play-" + String(format: "%012d", process.processIdentifier!))
        XCTAssertEqual(process.clientName?.count, "jack_play-".count + 12)
        await wait(box) { $0.contains(.ready(channels: 2, fileRate: 48000, serverRate: 48000, frames: 192000)) }
        process.send(.play)
        await wait(box) { $0.contains(.position(frame: 100, state: .playing)) }
        process.send(.seek(96000))
        await wait(box) { $0.contains(.position(frame: 96000, state: .paused)) }
        process.send(.pause)
        await wait(box) { $0.contains(.position(frame: 100, state: .paused)) }
        process.stop()
        await wait(box) { self.hasExit($0) }
        XCTAssertEqual(box.events.last, .exited(status: 0, requested: true))
        XCTAssertFalse(process.isRunning)
    }

    func testTheEventsComeInTheOrderTheProgramWroteThem() async throws {
        let (process, box) = try makeProcess()
        try process.start()
        await wait(box) { $0.count >= 3 }
        XCTAssertEqual(Array(box.events.prefix(3)), [.message("jack client name: fake"),
                                                      .ready(channels: 2, fileRate: 48000, serverRate: 48000, frames: 192000),
                                                      .position(frame: 0, state: .paused)])
        process.stop()
        await wait(box) { self.hasExit($0) }
    }

    func testAProgramThatEndsOnItsOwnIsNotARequestedStop() async throws {
        let (process, box) = try makeProcess(mode: "crash")
        try process.start()
        await wait(box) { self.hasExit($0) }
        XCTAssertEqual(box.events.last, .exited(status: 3, requested: false))
        XCTAssertTrue(box.events.contains(.warning("something went wrong")))
        // Everything it wrote came before the end was reported.
        XCTAssertTrue(box.events.contains(.ready(channels: 2, fileRate: 48000, serverRate: 48000, frames: 192000)))
    }

    func testAProgramThatIgnoresTheStopIsEnded() async throws {
        let (process, box) = try makeProcess(mode: "deaf")
        try process.start()
        await wait(box) { $0.contains(.position(frame: 0, state: .paused)) }
        process.stop(grace: 0.3)
        await wait(box, timeout: 5) { self.hasExit($0) }
        guard case .exited(_, let requested)? = box.events.last else { return XCTFail("\(box.events)") }
        XCTAssertTrue(requested)
    }

    func testClosingTheApplicationEndsTheProgram() async throws {
        let (process, box) = try makeProcess()
        try process.start()
        await wait(box) { $0.contains(.position(frame: 0, state: .paused)) }
        process.terminate()
        await wait(box) { self.hasExit($0) }
        XCTAssertFalse(process.isRunning)
    }

    func testSendingToAnEndedProgramDoesNothing() async throws {
        let (process, box) = try makeProcess(mode: "crash")
        try process.start()
        await wait(box) { self.hasExit($0) }
        process.send(.play)   // no crash, no SIGPIPE
        process.stop()
    }

    func testAMissingProgramIsReported() {
        let process = PlayerProcess(executable: URL(fileURLWithPath: "/nonexistent/jack_play"), command: PlayerCommand(file: URL(fileURLWithPath: "/tmp/x.wav")))
        XCTAssertThrowsError(try process.start()) { XCTAssertEqual($0 as? PlayerProcess.LaunchError, .executableNotFound) }
    }

    func testTheHelperIsFoundWhereTheApplicationKeepsIt() throws {
        let bundle = directory.appendingPathComponent("Fake.app")
        let helpers = bundle.appendingPathComponent("Contents/Helpers")
        try FileManager.default.createDirectory(at: helpers, withIntermediateDirectories: true)
        let helper = helpers.appendingPathComponent("jack_play")
        try "#!/bin/sh\n".write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
        XCTAssertEqual(PlayerHelper.executableURL(bundle: Bundle(url: bundle) ?? .main, environment: [:])?.lastPathComponent, "jack_play")
    }
}
