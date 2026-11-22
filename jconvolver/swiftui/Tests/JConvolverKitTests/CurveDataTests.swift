// SPDX-License-Identifier: GPL-3.0-or-later

import SoundFileKit
import XCTest
@testable import JConvolverKit

final class CurveDataTests: XCTestCase {
    func testColumnsKeepEveryPeak() {
        var s = [Float](repeating: 0.01, count: 1000)
        s[503] = 0.9
        s[777] = -0.7
        let data = CurveData(samples: s, sampleRate: 48000)
        let c = data.columns(from: 0, to: 1000, width: 10)
        XCTAssertEqual(c.maximums.max(), 0.9)
        XCTAssertEqual(c.minimums.min(), -0.7)
        XCTAssertEqual(c.maximums[5], 0.9)
        XCTAssertEqual(c.minimums[7], -0.7)
    }

    func testZoomedInColumnsFollowTheSamples() {
        let data = CurveData(samples: [0, 1, 0, -1], sampleRate: 48000)
        let c = data.columns(from: 0, to: 4, width: 8)
        XCTAssertEqual(c.maximums.count, 8)
        XCTAssertEqual(c.maximums[2], 1)
        XCTAssertEqual(c.minimums[6], -1)
    }

    func testDecibelScale() {
        let scale = CurveScale.decibels(floorDB: -90)
        XCTAssertEqual(scale.height(of: 1, reference: 1), 1, accuracy: 1e-9)
        XCTAssertEqual(scale.height(of: -0.001, reference: 1), -(30.0 / 90.0), accuracy: 1e-6)
        XCTAssertEqual(scale.height(of: 0, reference: 1), 0)
        XCTAssertEqual(scale.height(of: 1e-9, reference: 1), 0, accuracy: 1e-9)
        XCTAssertEqual(CurveScale.linear.height(of: 0.5, reference: 1), 0.5, accuracy: 1e-9)
    }
}

final class ChangeDirectoryWritingTests: XCTestCase {
    func testFilesOfAnotherFolderGetOneChangeDirectory() {
        var d = ConvDocument(inputs: 2, outputs: 2)
        d.add(ConvImpulse(source: .file(path: "/data/ir/a.wav", channel: 1)), at: ConvPair(input: 0, output: 0))
        d.add(ConvImpulse(source: .file(path: "/data/ir/b.wav", channel: 1)), at: ConvPair(input: 1, output: 1))
        d.add(ConvImpulse(source: .file(path: "here.wav", channel: 1)), at: ConvPair(input: 0, output: 1))
        let text = d.makeConfig(automatic: ConvHeader(partition: 256, maxLength: 1000)).text
        XCTAssertEqual(text.components(separatedBy: "/cd ").count - 1, 1)
        XCTAssertTrue(text.contains("/cd /data/ir"))
        XCTAssertTrue(text.contains(" a.wav"))
        XCTAssertFalse(text.contains("/data/ir/a.wav"))
        // The file of the folder of the configuration comes before the /cd.
        XCTAssertLessThan(text.range(of: "here.wav")!.lowerBound, text.range(of: "/cd /data/ir")!.lowerBound)
    }
}

final class LatencyBeyondFileTests: XCTestCase {
    func testShortFileIsFlaggedWhenCompensationExceedsIt() {
        let info = SoundFileInfo(channels: 1, sampleRate: 48000, frames: 512, container: "WAV", fileExtension: "wav", encoding: "float",
                                 bitsPerSample: 32, isLossy: false, sfFormat: 0)
        var d = ConvDocument(inputs: 1, outputs: 1)
        d.add(ConvImpulse(source: .file(path: "a.wav", channel: 1)), at: ConvPair(input: 0, output: 0))
        let context = ConvValidationContext(mode: .realTime(jackRate: 48000), configDirectory: "/x", latencyCompensation: 600, fileInfo: { _ in info })
        let problems = ConvValidator.problems(in: d, context: context)
        XCTAssertTrue(problems.contains { if case .latencyBeyondFile = $0.kind { true } else { false } })
        XCTAssertEqual(problems.first { if case .latencyBeyondFile = $0.kind { true } else { false } }?.severity, .error)
        // Enough delay: the engine takes away less.
        var e = ConvDocument(inputs: 1, outputs: 1)
        e.add(ConvImpulse(source: .file(path: "a.wav", channel: 1), delay: 300), at: ConvPair(input: 0, output: 0))
        XCTAssertFalse(ConvValidator.problems(in: e, context: context).contains { if case .latencyBeyondFile = $0.kind { true } else { false } })
    }
}

final class DistributeTests: XCTestCase {
    private func p(_ i: Int, _ o: Int) -> ConvPair { ConvPair(input: i, output: o) }
    private let a = Placeable.channel(path: "a.wav", channel: 1), b = Placeable.channel(path: "a.wav", channel: 2)

    func testOneThingGoesOnEveryPair() {
        let plan = Placement.distribute([a], over: [p(1, 1), p(0, 2), p(0, 0)])
        XCTAssertEqual(plan.items.map(\.pair), [p(0, 0), p(0, 2), p(1, 1)])
        XCTAssertEqual(plan.left, 0)
    }

    func testSeveralThingsFollowTheReadingOrderAndLeaveTheRestEmpty() {
        let plan = Placement.distribute([a, b], over: [p(0, 0), p(0, 1), p(1, 0), p(1, 1)])
        XCTAssertEqual(plan.items.map(\.pair), [p(0, 0), p(0, 1)])
        XCTAssertEqual(plan.left, 0)
        let columns = Placement.distribute([a, b], over: [p(0, 0), p(0, 1), p(1, 0), p(1, 1)], byColumns: true)
        XCTAssertEqual(columns.items.map(\.pair), [p(0, 0), p(1, 0)])
    }

    func testThingsLeftOverAreCounted() {
        let plan = Placement.distribute([a, b, .dirac], over: [p(0, 0), p(0, 1)])
        XCTAssertEqual(plan.items.count, 2)
        XCTAssertEqual(plan.left, 1)
    }
}

final class WiringTests: XCTestCase {
    private func document() -> ConvDocument { ConvDocument(inputs: 2, outputs: 3) }

    func testConnectionsAddAndLeave() {
        var d = document()
        d.toggleConnection("system:capture_1", .input, 0)
        d.toggleConnection("system:capture_2", .input, 0)
        XCTAssertEqual(d.connections(.input, 0), ["system:capture_1", "system:capture_2"], "a channel can have several ports")
        XCTAssertEqual(d.mixedInputs, [0])
        d.toggleConnection("system:capture_1", .input, 0)
        XCTAssertEqual(d.connections(.input, 0), ["system:capture_2"])
        d.toggleConnection("system:capture_2", .input, 0)
        XCTAssertTrue(d.connections(.input, 0).isEmpty)
    }

    func testDefaultPortNamesAndUnconnected() {
        var d = document()
        XCTAssertEqual(d.portName(.input, 1), "in-2")
        XCTAssertEqual(d.portName(.output, 2), "out-3")
        d.toggleConnection("system:playback_1", .output, 1)
        XCTAssertEqual(d.unconnectedChannels(.output), [0, 2])
    }

    func testSoundCardAndClear() {
        var d = document()
        d.toggleConnection("Max:in1", .output, 1)
        d.connectToSoundCard(.output, ports: ["system:playback_1", "system:playback_2"])
        XCTAssertEqual(d.connections(.output, 1), ["system:playback_2"], "back to the sound card leaves nothing else")
        XCTAssertTrue(d.connections(.output, 2).isEmpty, "no port left for the third output")
        d.clearConnections(.output)
        XCTAssertEqual(d.unconnectedChannels(.output), [0, 1, 2])
    }

    func testSummedDestinationsAndFileRoundTrip() throws {
        var d = document()
        d.toggleConnection("Max:in1", .output, 0)
        d.toggleConnection("Max:in1", .output, 1)
        d.toggleConnection("Max:in2", .output, 2)
        d.toggleConnection("Max:in 3", .output, 2)
        XCTAssertEqual(d.summedDestinations, ["Max:in1"])
        let text = d.makeConfig(automatic: d.automaticHeader(period: 256, lengthOfFile: { _ in nil })).text
        XCTAssertTrue(text.contains("/output/name 1 out-1 Max:in1"), text)
        XCTAssertTrue(text.contains("/output/name 3 out-3 Max:in2 \"Max:in 3\""), text)
        XCTAssertFalse(text.contains("/input/name"))
        // Read back: the same ports, in the same order.
        let config = ConvConfig.parse(text).config
        let back = ConvDocument.make(from: config).document
        XCTAssertEqual(back.connections(.output, 2), ["Max:in2", "Max:in 3"])
    }

    func testSeveralPortsOnALineAndComment() {
        let text = "/convolver/new 1 1 256 128\n/input/name 1 in a:out_1 \"b c:out 2\" '' # not a port\n"
        let back = ConvDocument.make(from: ConvConfig.parse(text).config).document
        XCTAssertEqual(back.connections(.input, 0), ["a:out_1", "b c:out 2"])
        XCTAssertEqual(ConfWord.split("a  \"b c\"  d"), ["a", "b c", "d"])
        XCTAssertNil(ConfWord.split("\"unclosed"))
        XCTAssertEqual(ConfWord.join(["a", "b c"]), "a \"b c\"")
    }
}
