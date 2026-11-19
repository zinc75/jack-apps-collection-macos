// SPDX-License-Identifier: MIT

import XCTest
@testable import JackBridge

/// A JACK graph in memory.
@MainActor
final class MemoryGraph: JackLinking {
    var outputs: Set<String> = []
    var inputs: Set<String> = []
    var links: Set<JackLink> = []
    var refused: Set<JackLink> = []
    var connectCalls = 0, disconnectCalls = 0

    func outputPorts() -> Set<String> { outputs }
    func inputPorts() -> Set<String> { inputs }
    func destinations(of output: String) -> Set<String> { Set(links.filter { $0.output == output }.map(\.input)) }
    struct Refused: Error {}
    func connect(from output: String, to input: String) throws {
        connectCalls += 1
        let l = JackLink(output: output, input: input)
        if refused.contains(l) { throw Refused() }
        links.insert(l)
    }
    func disconnect(from output: String, to input: String) throws { disconnectCalls += 1; links.remove(JackLink(output: output, input: input)) }
    /// A port leaves: JACK drops its connections.
    func remove(_ port: String) {
        outputs.remove(port); inputs.remove(port)
        links = links.filter { $0.output != port && $0.input != port }
    }
}

@MainActor
final class ConnectionReconcilerTests: XCTestCase {
    private func link(_ o: String, _ i: String) -> JackLink { JackLink(output: o, input: i) }

    func testTheWantedLinksAreMade() {
        let g = MemoryGraph(); g.outputs = ["p:out_1"]; g.inputs = ["a:in"]
        let r = ConnectionReconciler(linking: g, own: .output)
        r.reconcile(wanted: [link("p:out_1", "a:in")])
        XCTAssertEqual(g.links, [link("p:out_1", "a:in")])
        XCTAssertEqual(r.missingPorts, []); XCTAssertEqual(r.failures, [])
    }

    func testThePortOfTheOtherClientIsMissingButNotTheProgramsOwn() {
        let g = MemoryGraph(); g.outputs = []; g.inputs = ["a:in"]            // the program has not registered its output yet
        let r = ConnectionReconciler(linking: g, own: .output)
        r.reconcile(wanted: [link("p:out_1", "a:in"), link("p:out_1", "b:in")])
        XCTAssertEqual(r.missingPorts, ["b:in"], "b:in is the other client's, a:in is there, p:out_1 is the program's own")
        XCTAssertEqual(g.links, [])
        // The same for a program whose inputs are fed.
        let h = MemoryGraph(); h.outputs = ["a:out"]; h.inputs = []
        let s = ConnectionReconciler(linking: h, own: .input)
        s.reconcile(wanted: [link("a:out", "p:in_1"), link("b:out", "p:in_1")])
        XCTAssertEqual(s.missingPorts, ["b:out"])
    }

    func testWhatWasMissingIsMadeWhenItAppears() {
        let g = MemoryGraph(); g.outputs = ["p:out_1"]
        let r = ConnectionReconciler(linking: g, own: .output)
        r.reconcile(wanted: [link("p:out_1", "a:in")])
        XCTAssertEqual(r.missingPorts, ["a:in"])
        g.inputs = ["a:in"]
        r.reconcile(wanted: [link("p:out_1", "a:in")])
        XCTAssertEqual(g.links, [link("p:out_1", "a:in")]); XCTAssertEqual(r.missingPorts, [])
    }

    func testAnAlreadyMadeConnectionIsNotMadeAgain() {
        let g = MemoryGraph(); g.outputs = ["p:out_1"]; g.inputs = ["a:in"]
        let r = ConnectionReconciler(linking: g, own: .output)
        r.reconcile(wanted: [link("p:out_1", "a:in")]); r.reconcile(wanted: [link("p:out_1", "a:in")]); r.reconcile(wanted: [link("p:out_1", "a:in")])
        XCTAssertEqual(g.connectCalls, 1)
    }

    func testAConnectionFoundAlreadyThereIsKeptAndRemovedWhenNotWantedAnyMore() {
        let g = MemoryGraph(); g.outputs = ["p:out_1"]; g.inputs = ["a:in"]; g.links = [link("p:out_1", "a:in")]
        let r = ConnectionReconciler(linking: g, own: .output)
        r.reconcile(wanted: [link("p:out_1", "a:in")])
        XCTAssertEqual(g.connectCalls, 0)
        r.reconcile(wanted: [])
        XCTAssertEqual(g.links, [])
    }

    func testAConnectionThatLeftWithItsPortIsMadeAgainWhenThePortReturns() {
        let g = MemoryGraph(); g.outputs = ["p:out_1"]; g.inputs = ["a:in"]
        let r = ConnectionReconciler(linking: g, own: .output)
        let wanted: Set = [link("p:out_1", "a:in")]
        r.reconcile(wanted: wanted)
        g.remove("a:in")
        r.reconcile(wanted: wanted)
        XCTAssertEqual(r.missingPorts, ["a:in"])
        g.inputs.insert("a:in")
        r.reconcile(wanted: wanted)
        XCTAssertEqual(g.links, wanted); XCTAssertEqual(g.connectCalls, 2)
    }

    func testARefusalIsReportedForAPersonAndTheRestIsDone() {
        let g = MemoryGraph(); g.outputs = ["p:out_1", "p:out_2"]; g.inputs = ["a:in", "b:in"]
        g.refused = [link("p:out_1", "a:in")]
        let r = ConnectionReconciler(linking: g, own: .output)
        r.reconcile(wanted: [link("p:out_1", "a:in"), link("p:out_2", "b:in")])
        XCTAssertEqual(r.failures, ["p:out_1 → a:in"])
        XCTAssertEqual(g.links, [link("p:out_2", "b:in")])
    }

    func testSeveralOutputsCanFeedOnePort() {
        let g = MemoryGraph(); g.outputs = ["p:out_1", "p:out_2"]; g.inputs = ["x:in"]
        let r = ConnectionReconciler(linking: g, own: .output)
        r.reconcile(wanted: [link("p:out_1", "x:in"), link("p:out_2", "x:in")])
        XCTAssertEqual(g.links.count, 2)
    }

    func testAProgramWhosePortsAreKnownToExistNeedsNoCheck() {
        let g = MemoryGraph(); g.outputs = []; g.inputs = ["a:in"]            // the graph does not list the program's output
        let r = ConnectionReconciler(linking: g, own: .output, checksOwnPorts: false)
        r.reconcile(wanted: [link("p:out_1", "a:in")])
        XCTAssertEqual(g.links, [link("p:out_1", "a:in")])
        r.reconcile(wanted: [link("p:out_1", "a:in")])
        XCTAssertEqual(g.connectCalls, 1, "still not made twice")
    }

    func testResettingForgetsWhatWasMade() {
        let g = MemoryGraph(); g.outputs = ["p:out_1"]; g.inputs = ["a:in"]
        let r = ConnectionReconciler(linking: g, own: .output)
        r.reconcile(wanted: [link("p:out_1", "a:in")])
        r.reset()
        g.links = []                       // the program ended
        XCTAssertEqual(r.missingPorts, []); XCTAssertEqual(r.failures, [])
        r.reconcile(wanted: [link("p:out_1", "a:in")])
        XCTAssertEqual(g.links.count, 1, "made again, as if for the first time")
    }

    func testPortsAreGroupedByClientWithTheSoundCardFirst() {
        let groups = JackPortClient.group(ports: ["Carla:out1", "system:capture_1", "Carla:out2", "Ardour:out", "system:capture_2", "noclient"])
        XCTAssertEqual(groups.map(\.name), ["system", "Ardour", "Carla"])
        XCTAssertEqual(groups.first?.ports, ["capture_1", "capture_2"]); XCTAssertEqual(groups.first?.isSystem, true)
        XCTAssertEqual(groups.last?.fullName(of: "out2"), "Carla:out2")
    }
}
