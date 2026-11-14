// SPDX-License-Identifier: GPL-2.0-or-later
// Licence of the program this interface drives (klick).
import XCTest
@testable import KlickJack

final class JackPortTests: XCTestCase {
    func testTheListOfTheServerIsRead() {
        let text = "p\t1\tsystem:playback_1\np\t0\tsystem:playback_2\n-\t0\tReaper:in 1\n"
        let ports = JackPort.parse(text)
        XCTAssertEqual(ports, [
            JackPort(name: "system:playback_1", isPhysical: true, isConnected: true),
            JackPort(name: "system:playback_2", isPhysical: true, isConnected: false),
            JackPort(name: "Reaper:in 1", isPhysical: false, isConnected: false),
        ])
    }

    func testBrokenLinesAreLeftOut() {
        XCTAssertEqual(JackPort.parse(""), [])
        XCTAssertEqual(JackPort.parse("p\t1\n\nnonsense\n-\t0\t\n"), [], "a line without a name is no port")
    }

    func testAPortKnowsItsClient() {
        let port = JackPort(name: "a:b:c", isPhysical: false, isConnected: false)
        XCTAssertEqual(port.client, "a", "the client is what comes before the first colon")
        XCTAssertEqual(port.shortName, "b:c")
        let bare = JackPort(name: "alone", isPhysical: false, isConnected: false)
        XCTAssertEqual(bare.client, "alone")
        XCTAssertEqual(bare.shortName, "alone")
    }

    func testPortsAreGroupedByClientWithTheHardwareFirst() {
        let ports = JackPort.parse("-\t0\tReaper:in 1\n-\t0\tReaper:in 2\np\t1\tsystem:playback_1\np\t0\tsystem:playback_2\n-\t0\tArdour:in\n")
        let groups = JackClientPorts.grouped(ports)
        XCTAssertEqual(groups.map(\.name), ["system", "Reaper", "Ardour"], "the hardware first, then the order of the server")
        XCTAssertEqual(groups[0].ports.count, 2)
        XCTAssertEqual(groups[1].ports.map(\.shortName), ["in 1", "in 2"])
        XCTAssertTrue(groups[0].isPhysical)
        XCTAssertFalse(groups[1].isPhysical)
        XCTAssertEqual(JackClientPorts.grouped([]), [])
    }
}
