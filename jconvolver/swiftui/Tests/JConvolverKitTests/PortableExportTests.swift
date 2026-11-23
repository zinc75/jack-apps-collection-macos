// SPDX-License-Identifier: GPL-3.0-or-later

import SoundFileKit
import XCTest
@testable import JConvolverKit

final class PortableExportTests: XCTestCase {
    private var folder: URL!
    private var output: URL!
    private let automatic = ConvHeader(partition: 256, maxLength: 4000)

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("portable-\(UUID().uuidString)", isDirectory: true)
        folder = base.appendingPathComponent("source", isDirectory: true)
        output = base.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }

    private func info(_ path: String) -> SoundFileInfo? { try? SoundFile.probe(URL(fileURLWithPath: path)) }

    private func ramp(_ n: Int, from: Float) -> [Float] { (0..<n).map { from + Float($0) / 1000 } }

    /// Two files: a mono one of 100 frames, a stereo one of 60; three places read them, one of them twice the same channel.
    private func makeDocument(rate: Int = 48000) throws -> ConvDocument {
        try WAVSupport.write(folder.appendingPathComponent("a.wav"), channels: 1, rate: rate, samples: ramp(100, from: 0.1))
        var stereo: [Float] = []
        for i in 0..<60 { stereo.append(0.5 + Float(i) / 1000); stereo.append(-0.5 - Float(i) / 1000) }
        try WAVSupport.write(folder.appendingPathComponent("b.wav"), channels: 2, rate: rate, samples: stereo)
        var document = ConvDocument(inputs: 2, outputs: 2)
        document.add(ConvImpulse(source: .file(path: "a.wav", channel: 1)), at: ConvPair(input: 0, output: 0))
        document.add(ConvImpulse(source: .file(path: "b.wav", channel: 2), gain: 0.5, delay: 3, offset: 10, length: 20), at: ConvPair(input: 0, output: 1))
        document.add(ConvImpulse(source: .file(path: "a.wav", channel: 1), gain: 2), at: ConvPair(input: 1, output: 1))
        document.add(ConvImpulse(source: .dirac), at: ConvPair(input: 1, output: 0))
        return document
    }

    private func plan(_ document: ConvDocument, _ options: PortableOptions) -> PortablePlan {
        PortablePlan.make(document: document, options: options, configDirectory: folder.path, automatic: automatic, fileInfo: { self.info($0) })
    }

    private func read(_ url: URL) throws -> [[Float]] {
        let a = try CurveData.load(url: url, channel: 1)
        var channels = [a.samples]
        let count = try SoundFile.probe(url).channels
        if count > 1 { for c in 2...count { channels.append(try CurveData.load(url: url, channel: c).samples) } }
        return channels
    }

    func testOneChannelForEachDistinctResponseOfFile() throws {
        let document = try makeDocument()
        let p = plan(document, PortableOptions(name: "x"))
        XCTAssertTrue(p.blockers.isEmpty)
        // a.wav 1 (used twice), b.wav 2.
        XCTAssertEqual(p.channels, 2)
        XCTAssertEqual(p.impulses, 3)
        XCTAssertEqual(p.files, 2)
        XCTAssertEqual(p.frames, 100)
    }

    func testTheWrittenFilesHoldTheResponsesAndTheConfigurationReadsThem() throws {
        let document = try makeDocument()
        let options = PortableOptions(name: "room")
        let p = plan(document, options)
        let result = try PortableExporter.export(document: document, plan: p, options: options, configDirectory: folder.path, automatic: automatic,
                                                fileInfo: { self.info($0) }, to: output)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: output.path).sorted(), ["room.conf", "room.wav"])
        let audio = try XCTUnwrap(result.audio)
        let channels = try read(audio)
        XCTAssertEqual(channels.count, 2)
        XCTAssertEqual(channels[0].count, 100)
        XCTAssertEqual(channels[0][5], 0.105, accuracy: 1e-6)
        // The second channel is the right channel of b.wav, whole, padded with silence to the longest.
        XCTAssertEqual(channels[1][0], -0.5, accuracy: 1e-6)
        XCTAssertEqual(channels[1][59], -0.559, accuracy: 1e-6)
        XCTAssertEqual(channels[1][60], 0)

        let config = ConvConfig.parse(try String(contentsOf: try XCTUnwrap(result.configuration), encoding: .utf8)).config.text
        XCTAssertFalse(config.contains("/cd"))
        XCTAssertTrue(config.contains("/impulse/read 1 1 1 0 0 100 1 room.wav"), config)
        // The start, the length, the gain and the delay stay in the configuration, the channel is the one of the new file.
        XCTAssertTrue(config.contains("/impulse/read 1 2 0.5 3 10 20 2 room.wav"), config)
        // A response that read the whole of a shorter file says where it ends.
        XCTAssertTrue(config.contains("/impulse/read 2 2 2 0 0 100 1 room.wav"), config)
        XCTAssertTrue(config.contains("/impulse/dirac 2 1 1 0"), config)
    }

    func testTheFilesOfTheOriginalAreNotChanged() throws {
        let document = try makeDocument()
        let before = try Data(contentsOf: folder.appendingPathComponent("a.wav"))
        let options = PortableOptions(name: "room")
        _ = try PortableExporter.export(document: document, plan: plan(document, options), options: options, configDirectory: folder.path, automatic: automatic,
                                        fileInfo: { self.info($0) }, to: output)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("a.wav")), before)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted(), ["a.wav", "b.wav"])
    }

    func testWritingTheSettingsInTheSamplesGivesOneChannelForEachPlaceAndNoSetting() throws {
        let document = try makeDocument()
        let options = PortableOptions(name: "baked", appliesSettings: true)
        let p = plan(document, options)
        XCTAssertEqual(p.channels, 3)
        // The longest: the delay and the 20 frames of b.wav, the 100 of a.wav.
        XCTAssertEqual(p.frames, 100)
        let result = try PortableExporter.export(document: document, plan: p, options: options, configDirectory: folder.path, automatic: automatic,
                                                fileInfo: { self.info($0) }, to: output)
        let channels = try read(try XCTUnwrap(result.audio))
        XCTAssertEqual(channels.count, 3)
        // 1 → 1: a.wav as it is.
        XCTAssertEqual(channels[0][0], 0.1, accuracy: 1e-6)
        // 1 → 2: three frames of silence, then b.wav right channel from frame 10, times 0.5, for 20 frames.
        XCTAssertEqual(channels[1][2], 0)
        XCTAssertEqual(channels[1][3], -0.51 * 0.5, accuracy: 1e-6)
        XCTAssertEqual(channels[1][22], -0.529 * 0.5, accuracy: 1e-6)
        XCTAssertEqual(channels[1][23], 0)
        // 2 → 2: a.wav times 2 (the gain is above one: written as floats, not cut).
        XCTAssertEqual(channels[2][0], 0.2, accuracy: 1e-6)
        let config = try String(contentsOf: try XCTUnwrap(result.configuration), encoding: .utf8)
        XCTAssertTrue(config.contains("/impulse/read 1 2 1 0 0 23 2 baked.wav"), config)
    }

    func testPrecisionFollowsTheFilesOrIsFloat() throws {
        try WAVSupport.write(folder.appendingPathComponent("c.wav"), channels: 1, encoding: .int16, samples: ramp(10, from: 0.1))
        var document = ConvDocument(inputs: 1, outputs: 1)
        document.add(ConvImpulse(source: .file(path: "c.wav", channel: 1)), at: ConvPair(input: 0, output: 0))
        XCTAssertEqual(plan(document, PortableOptions(name: "x")).bytesPerSample, 2)
        XCTAssertEqual(plan(document, PortableOptions(name: "x", precision: .float32)).bytesPerSample, 4)
        let withFloat = try makeDocument()
        XCTAssertEqual(plan(withFloat, PortableOptions(name: "x")).bytesPerSample, 4)
    }

    func testWhatBlocksIsSaid() throws {
        var document = try makeDocument()
        document.add(ConvImpulse(source: .file(path: "missing.wav", channel: 1)), at: ConvPair(input: 0, output: 0))
        document.add(ConvImpulse(source: .file(path: "a.wav", channel: 4)), at: ConvPair(input: 1, output: 0))
        let blockers = plan(document, PortableOptions(name: "x")).blockers
        XCTAssertTrue(blockers.contains(.fileMissing(path: folder.appendingPathComponent("missing.wav").path)))
        XCTAssertTrue(blockers.contains(.channelMissing(path: folder.appendingPathComponent("a.wav").path, channel: 4, channels: 1)))
        XCTAssertEqual(plan(document, PortableOptions(name: "")).blockers.contains(.emptyName), true)
        XCTAssertThrowsError(try PortableExporter.export(document: document, plan: plan(document, PortableOptions(name: "x")), options: PortableOptions(name: "x"),
                                                         configDirectory: folder.path, automatic: automatic, fileInfo: { self.info($0) }, to: output))
    }

    func testFilesAtAnotherRateBlock() throws {
        var document = try makeDocument()
        try WAVSupport.write(folder.appendingPathComponent("d.wav"), channels: 1, rate: 44100, samples: ramp(10, from: 0.1))
        document.add(ConvImpulse(source: .file(path: "d.wav", channel: 1)), at: ConvPair(input: 0, output: 0))
        XCTAssertTrue(plan(document, PortableOptions(name: "x")).blockers.contains(.differentRates([44100, 48000])))
    }

    func testNoResponseFromAFileIsNothingToPutTogether() {
        var document = ConvDocument(inputs: 1, outputs: 1)
        document.add(ConvImpulse(source: .dirac), at: ConvPair(input: 0, output: 0))
        XCTAssertTrue(plan(document, PortableOptions(name: "x")).blockers.contains(.noFileImpulse))
    }

    func testTheArchiveHoldsTheTwoFilesAtItsRoot() throws {
        let document = try makeDocument()
        var options = PortableOptions(name: "room", output: .archiveOnly)
        let result = try PortableExporter.export(document: document, plan: plan(document, options), options: options, configDirectory: folder.path, automatic: automatic,
                                                fileInfo: { self.info($0) }, to: output)
        XCTAssertNil(result.audio)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: output.path), ["room.zip"])
        let listing = Process()
        listing.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        listing.arguments = ["-Z1", output.appendingPathComponent("room.zip").path]
        let pipe = Pipe(); listing.standardOutput = pipe
        try listing.run(); listing.waitUntilExit()
        let names = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)!.split(separator: "\n").map(String.init).sorted()
        XCTAssertEqual(names, ["room.conf", "room.wav"])

        options.output = .filesAndArchive
        try FileManager.default.removeItem(at: output.appendingPathComponent("room.zip"))
        _ = try PortableExporter.export(document: document, plan: plan(document, options), options: options, configDirectory: folder.path, automatic: automatic,
                                        fileInfo: { self.info($0) }, to: output)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: output.path).sorted(), ["room.conf", "room.wav", "room.zip"])
    }

    func testAnExistingFileIsReplacedAndNothingIsLeftBehind() throws {
        let document = try makeDocument()
        try Data("old".utf8).write(to: output.appendingPathComponent("room.conf"))
        let options = PortableOptions(name: "room")
        _ = try PortableExporter.export(document: document, plan: plan(document, options), options: options, configDirectory: folder.path, automatic: automatic,
                                        fileInfo: { self.info($0) }, to: output)
        XCTAssertNotEqual(try String(contentsOf: output.appendingPathComponent("room.conf"), encoding: .utf8), "old")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: output.path).sorted(), ["room.conf", "room.wav"])
    }

    func testTargetsListWhatIsWritten() throws {
        let document = try makeDocument()
        let p = plan(document, PortableOptions(name: "room"))
        XCTAssertEqual(PortableExporter.targets(plan: p, options: PortableOptions(name: "room", output: .filesAndArchive), in: output).map(\.lastPathComponent),
                       ["room.wav", "room.conf", "room.zip"])
        XCTAssertEqual(PortableExporter.targets(plan: p, options: PortableOptions(name: "room", output: .archiveOnly), in: output).map(\.lastPathComponent), ["room.zip"])
    }
}
