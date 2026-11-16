// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import JackPlayKit

final class ChannelRoutingTests: XCTestCase {
    private let playback = (1...8).map { "system:playback_\($0)" }

    func testTheDefaultSendsEachChannelToTheNextOutput() {
        XCTAssertEqual(DefaultRouting.make(channels: 2, playbackPorts: playback).channels, [["system:playback_1"], ["system:playback_2"]])
        XCTAssertEqual(DefaultRouting.make(channels: 6, playbackPorts: playback).connectedChannels, 6)
    }

    func testAMonoFileGoesToLeftAndRight() {
        XCTAssertEqual(DefaultRouting.make(channels: 1, playbackPorts: playback).channels, [["system:playback_1", "system:playback_2"]])
        XCTAssertEqual(DefaultRouting.make(channels: 1, playbackPorts: ["system:playback_1"]).channels, [["system:playback_1"]])
    }

    func testChannelsBeyondTheOutputsAreLeftUnconnected() {
        let r = DefaultRouting.make(channels: 9, playbackPorts: playback)
        XCTAssertEqual(r.connectedChannels, 8)
        XCTAssertEqual(r.channels[8], [])
        XCTAssertEqual(DefaultRouting.make(channels: 2, playbackPorts: []).connectedChannels, 0)
    }

    func testRoutingIsResizedForAnotherNumberOfChannels() {
        let r = ChannelRouting(channels: [["a:in"], ["b:in"], ["c:in"]])
        XCTAssertEqual(r.resized(to: 2).channels, [["a:in"], ["b:in"]])
        XCTAssertEqual(r.resized(to: 4).channels, [["a:in"], ["b:in"], ["c:in"], []])
        XCTAssertEqual(ChannelRouting.empty(channels: 3).connectedChannels, 0)
    }

    func testAChannelAndAPortAreConnectedOrNot() {
        var r = ChannelRouting.empty(channels: 2)
        r.toggle(channel: 0, port: "x:in_1")
        XCTAssertTrue(r.contains(channel: 0, port: "x:in_1"))
        XCTAssertFalse(r.contains(channel: 1, port: "x:in_1"))
        r.toggle(channel: 0, port: "x:in_1")
        XCTAssertFalse(r.contains(channel: 0, port: "x:in_1"))
        r.toggle(channel: 9, port: "x:in_1")   // no such channel: nothing happens
        XCTAssertEqual(r.connectedChannels, 0)
    }

    func testAPortThatReceivesSeveralChannelsIsReported() {
        let r = ChannelRouting(channels: [["x:in_1", "y:in_1"], ["x:in_1"], ["z:in_1"]])
        XCTAssertEqual(r.summedPorts, ["x:in_1"])
        XCTAssertEqual(r.clients, ["x", "y", "z"])
    }

    func testTheKeyOfAFileFollowsItsNameSizeAndDate() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("jackplay-key-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("a"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("b"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        let first = dir.appendingPathComponent("a/Intro.wav"), moved = dir.appendingPathComponent("b/Intro.wav")
        try Data(repeating: 1, count: 1000).write(to: first)
        try Data(repeating: 1, count: 1000).write(to: moved)
        for url in [first, moved] { try FileManager.default.setAttributes([.modificationDate: when], ofItemAtPath: url.path) }
        XCTAssertEqual(FileKey(url: first), FileKey(url: moved), "the folder does not count")
        XCTAssertEqual(FileKey(url: first), FileKey(name: "Intro.wav", size: 1000, modified: 1_700_000_000))
        try Data(repeating: 1, count: 2000).write(to: moved)
        XCTAssertNotEqual(FileKey(url: first), FileKey(url: moved), "a changed file is another file")
        XCTAssertEqual(FileKey(url: dir.appendingPathComponent("none.wav")).size, 0)
    }
}

final class ConnectionStoreTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let name = "jackplay-tests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        addTeardownBlock { d.removePersistentDomain(forName: name) }
        return d
    }

    private let key = FileKey(name: "Intro.wav", size: 100, modified: 5)
    private let routing = ChannelRouting(channels: [["system:playback_1"], ["system:playback_2"]])

    func testTheFirstTimeNothingIsRemembered() {
        XCTAssertNil(ConnectionStore(defaults: makeDefaults()).routing(for: key, channels: 2))
    }

    func testWhatIsRememberedComesBackAfterARestart() {
        let defaults = makeDefaults()
        ConnectionStore(defaults: defaults).remember(routing, for: key)
        XCTAssertEqual(ConnectionStore(defaults: defaults).routing(for: key, channels: 2), routing)
    }

    func testEachFileHasItsOwnConnections() {
        let store = ConnectionStore(defaults: makeDefaults())
        let other = FileKey(name: "Voix.wav", size: 50, modified: 9)
        store.remember(routing, for: key)
        store.remember(ChannelRouting(channels: [["Carla:in1"]]), for: other)
        XCTAssertEqual(store.routing(for: key, channels: 2), routing)
        XCTAssertEqual(store.routing(for: other, channels: 1)?.channels, [["Carla:in1"]])
    }

    func testTheNumberOfChannelsOfTheFileDecides() {
        let store = ConnectionStore(defaults: makeDefaults())
        store.remember(routing, for: key)
        XCTAssertEqual(store.routing(for: key, channels: 1)?.channels, [["system:playback_1"]])
        XCTAssertEqual(store.routing(for: key, channels: 3)?.channels.count, 3)
    }

    func testAFileCanBeForgotten() {
        let store = ConnectionStore(defaults: makeDefaults())
        store.remember(routing, for: key)
        store.forget(key)
        XCTAssertNil(store.routing(for: key, channels: 2))
    }

    func testOldFilesAreForgotten() {
        let defaults = makeDefaults()
        var date = Date(timeIntervalSince1970: 1_700_000_000)
        let old = ConnectionStore(defaults: defaults, now: { date })
        old.remember(routing, for: key)
        date.addTimeInterval(ConnectionStore.maxAge + 10)
        let later = ConnectionStore(defaults: defaults, now: { date })
        XCTAssertNil(later.routing(for: key, channels: 2))
        XCTAssertEqual(later.count, 0)
    }

    func testOnlyTheMostRecentFilesAreKept() {
        var date = Date(timeIntervalSince1970: 1_700_000_000)
        let store = ConnectionStore(defaults: makeDefaults(), now: { date })
        for i in 0..<(ConnectionStore.maxEntries + 10) {
            date.addTimeInterval(1)
            store.remember(routing, for: FileKey(name: "f\(i).wav", size: 1, modified: 1))
        }
        XCTAssertEqual(store.count, ConnectionStore.maxEntries)
        XCTAssertNil(store.routing(for: FileKey(name: "f0.wav", size: 1, modified: 1), channels: 2), "the oldest is gone")
        XCTAssertNotNil(store.routing(for: FileKey(name: "f\(ConnectionStore.maxEntries + 9).wav", size: 1, modified: 1), channels: 2))
    }
}

/// A JACK graph in memory.
@MainActor
final class FakeLinking: JackLinking {
    var inputs: Set<String> = []
    var links: Set<String> = []          // "output>input"
    var connectCalls = 0
    var refuse: Set<String> = []         // inputs that JACK refuses

    func inputPorts() -> Set<String> { inputs }
    func destinations(of output: String) -> Set<String> {
        Set(links.compactMap { $0.hasPrefix(output + ">") ? String($0.dropFirst(output.count + 1)) : nil })
    }
    func connect(from output: String, to input: String) throws {
        connectCalls += 1
        if refuse.contains(input) || !inputs.contains(input) { throw JackPlayTestError.refused }
        links.insert("\(output)>\(input)")
    }
    func disconnect(from output: String, to input: String) throws { links.remove("\(output)>\(input)") }
    /// A destination leaves: JACK removes its connections.
    func remove(_ port: String) { inputs.remove(port); links = links.filter { !$0.hasSuffix(">" + port) } }
}

enum JackPlayTestError: Error { case refused }

@MainActor
final class ConnectionManagerTests: XCTestCase {
    private let client = "jack_play-4242"

    private func make(inputs: [String]) -> (ConnectionManager, FakeLinking) {
        let fake = FakeLinking()
        fake.inputs = Set(inputs)
        return (ConnectionManager(linking: fake), fake)
    }

    func testTheRoutingIsMadeWhenThePlayerStarts() {
        let (manager, fake) = make(inputs: ["system:playback_1", "system:playback_2"])
        manager.attach(client: client, routing: ChannelRouting(channels: [["system:playback_1"], ["system:playback_2"]]))
        XCTAssertEqual(fake.links, ["jack_play-4242:out_1>system:playback_1", "jack_play-4242:out_2>system:playback_2"])
        XCTAssertTrue(manager.missingPorts.isEmpty)
    }

    func testADestinationThatIsNotThereYetIsConnectedWhenItAppears() {
        let (manager, fake) = make(inputs: ["system:playback_1"])
        manager.attach(client: client, routing: ChannelRouting(channels: [["system:playback_1", "Carla:in1"]]))
        XCTAssertEqual(manager.missingPorts, ["Carla:in1"])
        XCTAssertEqual(fake.links.count, 1)
        fake.inputs.insert("Carla:in1")
        manager.graphChanged()
        XCTAssertEqual(fake.links.count, 2)
        XCTAssertTrue(manager.missingPorts.isEmpty)
    }

    func testChangingTheRoutingConnectsAndDisconnects() {
        let (manager, fake) = make(inputs: ["a:in", "b:in", "c:in"])
        manager.attach(client: client, routing: ChannelRouting(channels: [["a:in"], ["b:in"]]))
        manager.update(routing: ChannelRouting(channels: [["a:in", "c:in"], []]))
        XCTAssertEqual(fake.links, ["jack_play-4242:out_1>a:in", "jack_play-4242:out_1>c:in"])
    }

    func testSeveralChannelsCanFeedOnePort() {
        let (manager, fake) = make(inputs: ["x:in"])
        manager.attach(client: client, routing: ChannelRouting(channels: [["x:in"], ["x:in"]]))
        XCTAssertEqual(fake.links.count, 2)
    }

    func testAConnectionAlreadyThereIsNotMadeAgain() {
        let (manager, fake) = make(inputs: ["a:in"])
        manager.attach(client: client, routing: ChannelRouting(channels: [["a:in"]]))
        XCTAssertEqual(fake.connectCalls, 1)
        manager.graphChanged()
        manager.graphChanged()
        XCTAssertEqual(fake.connectCalls, 1)
    }

    func testAConnectionJackRefusesIsReported() {
        let (manager, fake) = make(inputs: ["a:in", "b:in"])
        fake.refuse = ["b:in"]
        manager.attach(client: client, routing: ChannelRouting(channels: [["a:in", "b:in"]]))
        XCTAssertEqual(manager.failures, ["jack_play-4242:out_1 → b:in"])
        XCTAssertEqual(fake.links.count, 1)
    }

    func testADestinationThatLeavesAndComesBackIsConnectedAgain() {
        let (manager, fake) = make(inputs: ["Carla:in1"])
        manager.attach(client: client, routing: ChannelRouting(channels: [["Carla:in1"]]))
        fake.remove("Carla:in1")
        manager.graphChanged()
        XCTAssertEqual(manager.missingPorts, ["Carla:in1"])
        fake.inputs.insert("Carla:in1")
        manager.graphChanged()
        XCTAssertEqual(fake.links, ["jack_play-4242:out_1>Carla:in1"])
    }

    func testConnectionsFoundAlreadyMadeAreKept() {
        let (manager, fake) = make(inputs: ["a:in"])
        fake.links = ["jack_play-4242:out_1>a:in"]
        manager.attach(client: client, routing: ChannelRouting(channels: [["a:in"]]))
        XCTAssertEqual(fake.connectCalls, 0)
        manager.update(routing: ChannelRouting(channels: [[]]))
        XCTAssertTrue(fake.links.isEmpty, "the connection that was found is the manager's to remove")
    }

    func testNothingHappensAfterTheStop() {
        let (manager, fake) = make(inputs: ["a:in"])
        manager.attach(client: client, routing: ChannelRouting(channels: [["a:in"]]))
        manager.detach()
        fake.links = []
        manager.graphChanged()
        XCTAssertTrue(fake.links.isEmpty)
        XCTAssertNil(manager.clientName)
    }
}
