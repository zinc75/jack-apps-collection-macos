// SPDX-License-Identifier: GPL-3.0-or-later

import JackBridge
import XCTest
@testable import ZitaBridgeKit

@MainActor
final class FakeJack: JackLinking {
    var outputs: Set<String> = []
    var inputs: Set<String> = []
    var links: Set<String> = []          // "from→to"
    var refuse: Set<String> = []         // "from→to" that JACK refuses
    var connectCalls = [String](), disconnectCalls = [String]()

    func outputPorts() -> Set<String> { outputs }
    func inputPorts() -> Set<String> { inputs }
    func destinations(of output: String) -> Set<String> {
        Set(links.compactMap { l in let p = l.components(separatedBy: "→"); return p[0] == output ? p[1] : nil })
    }
    struct Refused: Error {}
    func connect(from output: String, to input: String) throws {
        if refuse.contains("\(output)→\(input)") { throw Refused() }
        connectCalls.append("\(output)→\(input)"); links.insert("\(output)→\(input)")
    }
    func disconnect(from output: String, to input: String) throws {
        disconnectCalls.append("\(output)→\(input)"); links.remove("\(output)→\(input)")
    }
}

@MainActor
final class WiringTests: XCTestCase {
    private func wiring(_ pairs: [(Int, String)]) -> ChannelWiring {
        var w = ChannelWiring(); for (c, p) in pairs { w.toggle(channel: c, port: p) }; return w
    }

    // MARK: ChannelWiring

    func testChannelsAreWiredAndUnwired() {
        var w = ChannelWiring()
        w.toggle(channel: 2, port: "system:playback_1")
        w.toggle(channel: 2, port: "Carla:in1")
        XCTAssertTrue(w.contains(channel: 2, port: "Carla:in1"))
        w.toggle(channel: 2, port: "Carla:in1")
        XCTAssertFalse(w.contains(channel: 2, port: "Carla:in1"))
        w.toggle(channel: 2, port: "system:playback_1")
        XCTAssertEqual(w, .empty, "a channel without port is not kept")
    }

    func testTheChannelsWithoutAPortAreReported() {
        let w = wiring([(1, "system:playback_1"), (4, "system:playback_2")])
        XCTAssertEqual(w.unwired(in: [1, 2, 4, 7]), [2, 7])
    }

    func testAPortThatTakesSeveralChannelsIsReportedAsSummed() {
        let w = wiring([(1, "system:playback_1"), (2, "system:playback_1"), (3, "system:playback_2")])
        XCTAssertEqual(w.summedPorts(in: [1, 2, 3]), ["system:playback_1"])
        XCTAssertEqual(w.summedPorts(in: [1, 3]), [], "channel 2 is not received")
    }

    func testTheWiringSurvivesBeingSavedAndIsReadable() throws {
        let w = wiring([(1, "system:playback_1"), (5, "Carla:in1"), (5, "Carla:in2")])
        let data = try JSONEncoder().encode(w)
        XCTAssertEqual(try JSONDecoder().decode(ChannelWiring.self, from: data), w)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("\"5\""), "keyed by the channel number: \(text)")
    }

    func testTheStoreRemembersEachDirection() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "zita-wiring-\(UUID().uuidString)"))
        let store = WiringStore(defaults: defaults)
        XCTAssertNil(store.wiring(for: .send))
        store.remember(wiring([(1, "system:capture_1")]), for: .send)
        store.remember(wiring([(1, "system:playback_1")]), for: .receive)
        XCTAssertEqual(store.wiring(for: .send), wiring([(1, "system:capture_1")]))
        XCTAssertEqual(WiringStore(defaults: defaults).wiring(for: .receive), wiring([(1, "system:playback_1")]))
    }

    func testTheFirstWiringFollowsTheSoundCard() {
        let w = DefaultWiring.make(channels: [1, 2, 5], systemPorts: ["system:playback_1", "system:playback_2"])
        XCTAssertEqual(w.ports, [1: ["system:playback_1"], 2: ["system:playback_2"]], "no port left for the third")
    }

    // MARK: The sender: other outputs feed in_N

    func testTheSenderIsFedBySourcesOfOtherClients() {
        let jack = FakeJack()
        jack.outputs = ["system:capture_1", "system:capture_2"]
        jack.inputs = ["zita-j2n:in_1", "zita-j2n:in_2"]
        let m = WiringManager(direction: .send, linking: jack)
        m.attach(client: "zita-j2n", channels: [1, 2], wiring: wiring([(1, "system:capture_1"), (2, "system:capture_2")]))
        XCTAssertEqual(jack.links, ["system:capture_1→zita-j2n:in_1", "system:capture_2→zita-j2n:in_2"])
        XCTAssertEqual(m.missingPorts, []); XCTAssertEqual(m.failures, [])
    }

    // MARK: The receiver: out_N feed other inputs

    func testTheReceiverFeedsInputsOfOtherClients() {
        let jack = FakeJack()
        jack.outputs = ["zita-n2j:out_1", "zita-n2j:out_5"]
        jack.inputs = ["system:playback_1", "Carla:in1"]
        let m = WiringManager(direction: .receive, linking: jack)
        m.attach(client: "zita-n2j", channels: [1, 5], wiring: wiring([(1, "system:playback_1"), (5, "Carla:in1"), (5, "Carla:in2")]))
        XCTAssertEqual(jack.links, ["zita-n2j:out_1→system:playback_1", "zita-n2j:out_5→Carla:in1"])
        XCTAssertEqual(m.missingPorts, ["Carla:in2"], "Carla has no second input yet")
    }

    func testTheChannelsTheProgramDoesNotHaveAreNotWired() {
        let jack = FakeJack()
        jack.outputs = ["zita-n2j:out_1"]; jack.inputs = ["system:playback_1", "system:playback_2"]
        let m = WiringManager(direction: .receive, linking: jack)
        m.attach(client: "zita-n2j", channels: [1], wiring: wiring([(1, "system:playback_1"), (2, "system:playback_2")]))
        XCTAssertEqual(jack.links, ["zita-n2j:out_1→system:playback_1"], "channel 2 is not received")
        XCTAssertEqual(m.missingPorts, [])
    }

    // MARK: Time

    func testWhatIsMissingIsMadeWhenItAppears() {
        let jack = FakeJack()
        jack.outputs = ["system:capture_1"]            // the program has not registered its ports yet
        let m = WiringManager(direction: .send, linking: jack)
        m.attach(client: "zita-j2n", channels: [1], wiring: wiring([(1, "system:capture_1")]))
        XCTAssertEqual(jack.links, []); XCTAssertEqual(m.missingPorts, [], "its own port is not a missing port of the wiring")
        jack.inputs = ["zita-j2n:in_1"]
        m.graphChanged()
        XCTAssertEqual(jack.links, ["system:capture_1→zita-j2n:in_1"])
    }

    func testAnApplicationThatComesLaterIsConnectedWhenItArrives() {
        let jack = FakeJack()
        jack.outputs = ["zita-n2j:out_1"]
        let m = WiringManager(direction: .receive, linking: jack)
        m.attach(client: "zita-n2j", channels: [1], wiring: wiring([(1, "Carla:in1")]))
        XCTAssertEqual(m.missingPorts, ["Carla:in1"])
        jack.inputs = ["Carla:in1"]
        m.graphChanged()
        XCTAssertEqual(jack.links, ["zita-n2j:out_1→Carla:in1"]); XCTAssertEqual(m.missingPorts, [])
    }

    func testAConnectionThatLeftWithItsPortIsMadeAgainWhenThePortReturns() {
        let jack = FakeJack()
        jack.outputs = ["zita-n2j:out_1"]; jack.inputs = ["Carla:in1"]
        let m = WiringManager(direction: .receive, linking: jack)
        m.attach(client: "zita-n2j", channels: [1], wiring: wiring([(1, "Carla:in1")]))
        jack.inputs = []; jack.links = []          // Carla quits: JACK drops the connection
        m.graphChanged()
        XCTAssertEqual(m.missingPorts, ["Carla:in1"])
        jack.inputs = ["Carla:in1"]
        m.graphChanged()
        XCTAssertEqual(jack.links, ["zita-n2j:out_1→Carla:in1"])
        XCTAssertEqual(jack.connectCalls.count, 2)
    }

    func testTheMatrixChangesTheConnections() {
        let jack = FakeJack()
        jack.outputs = ["zita-n2j:out_1"]; jack.inputs = ["system:playback_1", "system:playback_2"]
        let m = WiringManager(direction: .receive, linking: jack)
        m.attach(client: "zita-n2j", channels: [1], wiring: wiring([(1, "system:playback_1")]))
        m.update(wiring: wiring([(1, "system:playback_2")]))
        XCTAssertEqual(jack.links, ["zita-n2j:out_1→system:playback_2"])
        XCTAssertEqual(jack.disconnectCalls, ["zita-n2j:out_1→system:playback_1"])
    }

    func testWhatWasAlreadyConnectedIsKeptAndCanBeRemoved() {
        let jack = FakeJack()
        jack.outputs = ["zita-n2j:out_1"]; jack.inputs = ["system:playback_1"]
        jack.links = ["zita-n2j:out_1→system:playback_1"]   // made by a previous run of the program
        let m = WiringManager(direction: .receive, linking: jack)
        m.attach(client: "zita-n2j", channels: [1], wiring: wiring([(1, "system:playback_1")]))
        XCTAssertEqual(jack.connectCalls, [], "no second connection")
        m.update(wiring: .empty)
        XCTAssertEqual(jack.links, [])
    }

    func testARefusalIsReportedAndTheRestIsDone() {
        let jack = FakeJack()
        jack.outputs = ["zita-n2j:out_1", "zita-n2j:out_2"]; jack.inputs = ["a:in", "b:in"]
        jack.refuse = ["zita-n2j:out_1→a:in"]
        let m = WiringManager(direction: .receive, linking: jack)
        m.attach(client: "zita-n2j", channels: [1, 2], wiring: wiring([(1, "a:in"), (2, "b:in")]))
        XCTAssertEqual(m.failures, ["zita-n2j:out_1 → a:in"], "written for a person, with spaces")
        XCTAssertEqual(jack.links, ["zita-n2j:out_2→b:in"])
    }

    func testWhenTheProgramRestartsTheWiringIsMadeAgain() {
        let jack = FakeJack()
        jack.outputs = ["zita-n2j:out_1"]; jack.inputs = ["system:playback_1"]
        let m = WiringManager(direction: .receive, linking: jack)
        m.attach(client: "zita-n2j", channels: [1], wiring: wiring([(1, "system:playback_1")]))
        m.detach(); jack.links = []                // the program ended: its connections went
        XCTAssertEqual(m.clientName, nil); XCTAssertEqual(m.missingPorts, [])
        m.graphChanged()
        XCTAssertEqual(jack.links, [], "nothing is done while the program does not run")
        m.attach(client: "zita-n2j", channels: [1], wiring: wiring([(1, "system:playback_1")]))
        XCTAssertEqual(jack.links, ["zita-n2j:out_1→system:playback_1"])
    }
}
