// SPDX-License-Identifier: GPL-3.0-or-later

import JackBridge
import XCTest
@testable import ZitaBridgeKit

@MainActor
final class WiringRealityTests: XCTestCase {
    private func wiring(_ pairs: [(Int, String)]) -> ChannelWiring {
        var w = ChannelWiring(); for (c, p) in pairs { w.toggle(channel: c, port: p) }; return w
    }

    // MARK: Links into a wiring

    func testTheLinksOfTheSenderBecomeItsWiring() {
        let links: Set<JackLink> = [
            JackLink(output: "system:capture_1", input: "zita-j2n:in_1"),
            JackLink(output: "Carla:out1", input: "zita-j2n:in_1"),
            JackLink(output: "system:capture_2", input: "zita-j2n:in_2"),
            JackLink(output: "system:capture_3", input: "zita-j2n:in_3"),     // a channel the program does not have
            JackLink(output: "system:capture_1", input: "other:in_1"),          // not a port of the program
        ]
        let w = ChannelWiring(links: links, direction: .send, client: "zita-j2n", channels: [1, 2])
        XCTAssertEqual(w, wiring([(1, "Carla:out1"), (1, "system:capture_1"), (2, "system:capture_2")]))
    }

    func testTheLinksOfTheReceiverBecomeItsWiring() {
        let links: Set<JackLink> = [
            JackLink(output: "zita-n2j:out_1", input: "system:playback_1"),
            JackLink(output: "zita-n2j:out_2", input: "Carla:in1"),
            JackLink(output: "zita-n2j:out_2", input: "system:playback_2"),
            JackLink(output: "other:out_1", input: "system:playback_1"),
        ]
        let w = ChannelWiring(links: links, direction: .receive, client: "zita-n2j", channels: [1, 2])
        XCTAssertEqual(w.ports[1], ["system:playback_1"])
        XCTAssertEqual(w.ports[2], ["Carla:in1", "system:playback_2"])
    }

    // MARK: Differences

    func testWhatWasMadeOrRemovedElsewhereIsTold() {
        let wanted = wiring([(1, "system:playback_1"), (2, "system:playback_2")])
        let actual = wiring([(1, "system:playback_1"), (2, "Carla:in1")])
        let d = WiringDifferences(wiring: wanted, actual: actual, channels: [1, 2]) { _, _ in true }
        XCTAssertEqual(d.missing, wiring([(2, "system:playback_2")]), "wanted, and gone from JACK")
        XCTAssertEqual(d.foreign, wiring([(2, "Carla:in1")]), "in JACK, and not wanted")
        XCTAssertEqual(d.missingCount, 1)
        XCTAssertEqual(d.foreignCount, 1)
        XCTAssertFalse(d.isEmpty)
    }

    func testAConnectionWhosePortIsNotThereIsNotADifference() {
        let wanted = wiring([(1, "Carla:in1")])
        let d = WiringDifferences(wiring: wanted, actual: .empty, channels: [1]) { _, port in port != "Carla:in1" }
        XCTAssertTrue(d.isEmpty, "it is made when the port comes")
    }

    func testWhatIsTheSameIsNoDifference() {
        let w = wiring([(1, "a:in"), (2, "b:in")])
        XCTAssertTrue(WiringDifferences(wiring: w, actual: w, channels: [1, 2]) { _, _ in true }.isEmpty)
    }

    func testOnlyTheChannelsOfTheProgramAreCompared() {
        let d = WiringDifferences(wiring: wiring([(5, "a:in")]), actual: .empty, channels: [1, 2]) { _, _ in true }
        XCTAssertTrue(d.isEmpty)
    }

    // MARK: The manager

    func testTheManagerSeesAConnectionMadeElsewhere() {
        let jack = FakeJack()
        jack.outputs = ["system:capture_1", "system:capture_2"]; jack.inputs = ["zita-j2n:in_1", "zita-j2n:in_2"]
        let m = WiringManager(direction: .send, linking: jack)
        m.attach(client: "zita-j2n", channels: [1, 2], wiring: wiring([(1, "system:capture_1")]))
        XCTAssertTrue(m.refreshReality().isEmpty, "what the application made is what the wiring says")
        // Another tool connects a source to the second channel.
        jack.links.insert("system:capture_2→zita-j2n:in_2")
        let d = m.refreshReality()
        XCTAssertEqual(d.foreign, wiring([(2, "system:capture_2")]))
        XCTAssertTrue(d.missing.ports.isEmpty)
        XCTAssertEqual(m.differences, d)
    }

    func testTheManagerSeesAConnectionRemovedElsewhere() {
        let jack = FakeJack()
        jack.outputs = ["zita-n2j:out_1"]; jack.inputs = ["system:playback_1"]
        let m = WiringManager(direction: .receive, linking: jack)
        m.attach(client: "zita-n2j", channels: [1], wiring: wiring([(1, "system:playback_1")]))
        XCTAssertTrue(m.refreshReality().isEmpty)
        jack.links.remove("zita-n2j:out_1→system:playback_1")
        XCTAssertEqual(m.refreshReality().missing, wiring([(1, "system:playback_1")]))
        // The sound card goes away: the connection is not missing, it waits for the port.
        jack.inputs = []
        XCTAssertTrue(m.refreshReality().isEmpty)
    }

    func testNothingIsComparedWhileTheProgramDoesNotRun() {
        let jack = FakeJack()
        jack.outputs = ["system:capture_1"]; jack.inputs = []
        let m = WiringManager(direction: .send, linking: jack)
        XCTAssertTrue(m.refreshReality().isEmpty, "the wiring is prepared in advance")
        m.attach(client: "zita-j2n", channels: [1], wiring: wiring([(1, "system:capture_1")]))
        jack.inputs = ["zita-j2n:in_1"]
        jack.links.insert("system:capture_1→zita-j2n:in_1")
        jack.links.insert("other:out→zita-j2n:in_1")
        jack.outputs.insert("other:out")
        XCTAssertEqual(m.refreshReality().foreign, wiring([(1, "other:out")]))
        m.detach()
        XCTAssertTrue(m.differences.isEmpty)
    }
}
