// SPDX-License-Identifier: GPL-3.0-or-later

import JackBridge
import XCTest
@testable import JConvolverKit

final class WiringAdoptionTests: XCTestCase {
    private func link(_ o: String, _ i: String) -> JackLink { JackLink(output: o, input: i) }
    private let outputs: Set<String> = ["system:capture_1", "app:out", "jconvolver:out-1"]
    private let inputs: Set<String> = ["jconvolver:in-1", "system:playback_1", "mon:in"]

    func testAConnectionMadeElsewhereIsAdopted() {
        let wanted: Set<JackLink> = [link("system:capture_1", "jconvolver:in-1")]
        let links: Set<JackLink> = wanted.union([link("jconvolver:out-1", "mon:in")])
        let adopted = WiringAdoption.adopted(wanted: wanted, links: links, ownClient: "jconvolver", outputs: outputs, inputs: inputs)
        XCTAssertEqual(adopted, links)
    }

    func testAConnectionRemovedElsewhereIsNoLongerWanted() {
        let wanted: Set<JackLink> = [link("system:capture_1", "jconvolver:in-1"), link("jconvolver:out-1", "system:playback_1")]
        let links: Set<JackLink> = [link("jconvolver:out-1", "system:playback_1")]
        XCTAssertEqual(WiringAdoption.adopted(wanted: wanted, links: links, ownClient: "jconvolver", outputs: outputs, inputs: inputs), links)
    }

    func testAConnectionToAPortThatIsNotThereKeepsItsPlace() {
        let wanted: Set<JackLink> = [link("Later:out", "jconvolver:in-1")]
        XCTAssertEqual(WiringAdoption.adopted(wanted: wanted, links: [], ownClient: "jconvolver", outputs: outputs, inputs: inputs), wanted)
    }

    func testTheConnectionsOfOtherClientsAreNotTheEngines() {
        let links: Set<JackLink> = [link("app:out", "mon:in")]
        XCTAssertEqual(WiringAdoption.adopted(wanted: [], links: links, ownClient: "jconvolver", outputs: outputs, inputs: inputs), [])
    }

    func testAnEngineThatIsNamedLikeAnotherOneByItsBeginningIsNotConfused() {
        // "jconvolver-01" is another client: its connections are not the ones of "jconvolver:".
        let links: Set<JackLink> = [link("system:capture_1", "jconvolver-01:in-1")]
        XCTAssertEqual(WiringAdoption.adopted(wanted: [], links: links, ownClient: "jconvolver", outputs: outputs, inputs: inputs), [])
    }

    func testThePortsThatStayKeepTheirOrderAndTheNewOnesFollowByName() {
        XCTAssertEqual(WiringAdoption.ordered(["b", "a", "c"], ["a", "c", "z", "d"]), ["a", "c", "d", "z"])
        XCTAssertEqual(WiringAdoption.ordered(["x", "y"], []), [])
    }
}
