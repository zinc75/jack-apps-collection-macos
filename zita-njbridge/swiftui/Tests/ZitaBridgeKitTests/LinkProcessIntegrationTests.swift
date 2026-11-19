// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import ZitaBridgeKit

/// The real programs (the universal binaries of zita-njbridge/build), on a JACK server of their own so that the one of the
/// person is not touched. Skipped when a program or jackd is not there.
@MainActor
final class LinkProcessIntegrationTests: XCTestCase {
    private func program(_ p: BridgeCommand.Program) throws -> URL {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("build/\(p.rawValue)")
        guard FileManager.default.isExecutableFile(atPath: url.path) else { throw XCTSkip("zita-njbridge/build/\(p.rawValue) is not built") }
        return url
    }

    private func startServer(name: String, period: Int = 256) throws -> Process {
        let jackd = ["/usr/local/bin/jackd", "/opt/homebrew/bin/jackd"].first { FileManager.default.isExecutableFile(atPath: $0) }
        guard let jackd else { throw XCTSkip("jackd is not installed") }
        let server = Process()
        server.executableURL = URL(fileURLWithPath: jackd)
        server.arguments = ["-n", name, "-d", "dummy", "-r", "48000", "-p", "\(period)"]
        server.standardOutput = FileHandle.nullDevice
        server.standardError = FileHandle.nullDevice
        try server.run()
        Thread.sleep(forTimeInterval: 2)
        return server
    }

    final class Box { var events = [LinkEvent]() }

    private func wait(_ box: Box, timeout: TimeInterval = 10, _ what: String, for condition: @escaping ([LinkEvent]) -> Bool) async {
        let end = Date().addingTimeInterval(timeout)
        while !condition(box.events), Date() < end { try? await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertTrue(condition(box.events), "\(what): \(box.events.suffix(8))")
    }

    private func randomPort() -> Int { 20000 + Int.random(in: 0..<20000) }

    private func settings(port: Int) -> (SendSettings, ReceiveSettings) {
        var s = SendSettings(); s.address = "127.0.0.1"; s.port = port
        var r = ReceiveSettings(); r.address = "127.0.0.1"; r.port = port
        return (s, r)
    }

    private func isAlive(_ pid: Int32) -> Bool { kill(pid, 0) == 0 }

    // MARK: A link between a sender and a receiver

    func testASenderAndAReceiverLinkUpAndTheMarginIsRead() async throws {
        let n2j = try program(.receiver), j2n = try program(.sender)
        let serverName = "zbtest\(UUID().uuidString.prefix(6))"
        let server = try startServer(name: serverName)
        defer { server.terminate(); server.waitUntilExit() }
        let (s, r) = settings(port: randomPort())

        let receiver = LinkProcess(executable: n2j, command: BridgeCommand(receiver: r, jackServer: serverName))
        let rbox = Box()
        receiver.onEvent = { rbox.events.append($0) }
        try receiver.start()
        await wait(rbox, "the receiver waits") { $0.contains(.waitingForSender) }

        let sender = LinkProcess(executable: j2n, command: BridgeCommand(sender: s, jackServer: serverName))
        let sbox = Box()
        sender.onEvent = { sbox.events.append($0) }
        try sender.start()

        await wait(rbox, "the sender is found") { $0.contains(.senderFound(address: "127.0.0.1", channels: 2, rate: 48000)) }
        await wait(rbox, "syncing then receiving") { e in
            guard let a = e.firstIndex(of: .syncing), let b = e.firstIndex(of: .receiving) else { return false }
            return a < b
        }
        await wait(rbox, "statistics with a margin") { e in
            e.contains { if case .statistics(let st) = $0 { return st.frames > 0 && st.periods > 0 }; return false }
        }
        let stats = rbox.events.compactMap { e -> LinkStatistics? in if case .statistics(let st) = e { return st }; return nil }
        let margin = try XCTUnwrap(stats.last).margin(senderRate: 48000)
        XCTAssertGreaterThan(margin, 0.5)
        XCTAssertLessThan(margin, 40, "a margin of tens of milliseconds at a period of 256 means something is wrong")
        XCTAssertTrue(sbox.events.allSatisfy { if case .warning = $0 { return true }; return false }, "the sender says nothing: \(sbox.events)")

        // Stopping them: the end is said, and it is the one that was asked for.
        sender.stop(); receiver.stop()
        await wait(sbox, "the sender ended") { $0.contains(.exited(status: 130, requested: true)) || $0.contains { if case .exited(_, true) = $0 { return true }; return false } }
        await wait(rbox, "the receiver ended") { $0.contains { if case .exited(_, true) = $0 { return true }; return false } }
        XCTAssertFalse(receiver.isRunning); XCTAssertFalse(sender.isRunning)
    }

    func testTheReceiverSaysWhenTheSenderStops() async throws {
        let n2j = try program(.receiver), j2n = try program(.sender)
        let serverName = "zbtest\(UUID().uuidString.prefix(6))"
        let server = try startServer(name: serverName)
        defer { server.terminate(); server.waitUntilExit() }
        let (s, r) = settings(port: randomPort())
        let receiver = LinkProcess(executable: n2j, command: BridgeCommand(receiver: r, jackServer: serverName))
        let rbox = Box(); receiver.onEvent = { rbox.events.append($0) }
        try receiver.start()
        let sender = LinkProcess(executable: j2n, command: BridgeCommand(sender: s, jackServer: serverName))
        try sender.start()
        await wait(rbox, "receiving") { $0.contains(.receiving) }
        sender.stop()
        // The receiver notices after a while: it either says so or waits to start again.
        await wait(rbox, timeout: 20, "the loss of the sender") { e in
            e.contains(.transmitterEnded) || e.contains { if case .retrying = $0 { return true }; return false }
        }
        receiver.stop()
        await wait(rbox, "the receiver ended") { $0.contains { if case .exited = $0 { return true }; return false } }
    }

    // MARK: The models on the real programs

    func testTheModelsLinkUpAndAskForARestartWhenSettingsChange() async throws {
        let n2j = try program(.receiver), j2n = try program(.sender)
        let serverName = "zbtest\(UUID().uuidString.prefix(6))"
        let server = try startServer(name: serverName)
        defer { server.terminate(); server.waitUntilExit() }
        let (s, r) = settings(port: randomPort())
        let receiver = ReceiverModel(settings: r, executable: n2j, jackServer: serverName)
        let sender = SenderModel(settings: s, executable: j2n, jackServer: serverName)

        receiver.start()
        XCTAssertEqual(receiver.state, .waiting)
        sender.start()
        XCTAssertEqual(sender.state, .linked)
        let end = Date().addingTimeInterval(10)
        while receiver.state != .linked || receiver.marginHistory.count < 3, Date() < end { try await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertEqual(receiver.state, .linked)
        XCTAssertEqual(receiver.sender?.channels, 2); XCTAssertEqual(receiver.sender?.rate, 48000)
        XCTAssertEqual(receiver.filterDelay, 32)
        XCTAssertGreaterThan(try XCTUnwrap(receiver.margin), 0.5)
        XCTAssertEqual(receiver.interruptions, 0)
        XCTAssertFalse(receiver.needsRestart)
        XCTAssertFalse(receiver.canStart, "it already runs")

        receiver.settings.bufferMilliseconds = 30
        XCTAssertTrue(receiver.needsRestart, "the program runs with the old buffer")

        receiver.stop(); sender.stop()
        let stopEnd = Date().addingTimeInterval(8)
        while receiver.state != .stopped || sender.state != .stopped, Date() < stopEnd { try await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertEqual(receiver.state, .stopped); XCTAssertEqual(sender.state, .stopped)
        XCTAssertFalse(receiver.needsRestart, "nothing runs any more")
        XCTAssertNil(receiver.margin)
    }

    // MARK: When it cannot run

    func testWithoutAJackServerTheProgramSaysWhy() async throws {
        let n2j = try program(.receiver)
        let (_, r) = settings(port: randomPort())
        let receiver = LinkProcess(executable: n2j, command: BridgeCommand(receiver: r, jackServer: "no-such-server-\(UUID().uuidString.prefix(6))"))
        let box = Box(); receiver.onEvent = { box.events.append($0) }
        try receiver.start()
        await wait(box, "the reason") { $0.contains { if case .error(let t) = $0 { return t.hasPrefix("Can't connect to Jack") }; return false } }
        await wait(box, "the end, not asked for") { $0.contains { if case .exited(let status, false) = $0 { return status != 0 }; return false } }
        XCTAssertFalse(receiver.isRunning)
    }

    func testAnAddressThatDoesNotResolveIsReportedBeforeAnythingElse() async throws {
        let n2j = try program(.receiver)
        var r = ReceiveSettings(); r.address = "no.such.host.invalid"; r.port = randomPort()
        let receiver = LinkProcess(executable: n2j, command: BridgeCommand(receiver: r))
        let box = Box(); receiver.onEvent = { box.events.append($0) }
        try receiver.start()
        await wait(box, "the reason") { $0.contains(.error("Address resolution failed.")) }
        await wait(box, "the end") { $0.contains { if case .exited = $0 { return true }; return false } }
    }

    func testAProgramThatIsNotThereIsRefusedAtOnce() {
        let link = LinkProcess(executable: URL(fileURLWithPath: "/nonexistent/zita-n2j"), command: BridgeCommand(receiver: ReceiveSettings()))
        XCTAssertThrowsError(try link.start()) { XCTAssertEqual($0 as? LinkProcess.LaunchError, .executableNotFound) }
        XCTAssertFalse(link.isRunning)
    }

    // MARK: It cannot outlive the application

    func testTheProgramEndsWhenTheApplicationLetsGo() async throws {
        let n2j = try program(.receiver)
        let serverName = "zbtest\(UUID().uuidString.prefix(6))"
        let server = try startServer(name: serverName)
        defer { server.terminate(); server.waitUntilExit() }
        let (_, r) = settings(port: randomPort())
        var link: LinkProcess? = LinkProcess(executable: n2j, command: BridgeCommand(receiver: r, jackServer: serverName))
        let box = Box(); link?.onEvent = { box.events.append($0) }
        try link?.start()
        await wait(box, "waiting") { $0.contains(.waitingForSender) }
        let pid = try XCTUnwrap(link?.processIdentifier)
        XCTAssertTrue(isAlive(pid))
        link = nil   // what a crash does: the pseudo-terminal is closed
        let end = Date().addingTimeInterval(5)
        while isAlive(pid), Date() < end { try await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertFalse(isAlive(pid), "the program was left running")
    }
}
