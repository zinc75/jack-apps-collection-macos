// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import JConvolverKit

final class ConvDocumentTests: XCTestCase {
    private func document(_ text: String) -> ConvDocument { ConvDocument.make(from: ConvConfig.parse(text).config).document }
    private func pair(_ i: Int, _ o: Int) -> ConvPair { ConvPair(input: i, output: o) }
    private let automatic = ConvHeader(partition: 256, maxLength: 4096, density: 0.5)

    private let sample = """
    # reverb of a chapel
    # two by two

    /jack/client chapel
    /convolver/new 2 2 256 115200 1
    /input/name 1 "In L" system:capture_1
    /output/name 2 Out.R
    /cd /Users/eric/IR
    /impulse/read 1 1 0.5 0 0 0 1 chapel.wav
    /impulse/read 2 2 0.5 0 0 0 2 chapel.wav
    /impulse/read 1 2 0.25 0 100 5000 2 chapel.wav
    /impulse/dirac 2 1 1 10
    /impulse/copy 2 1 1 1
    """

    // MARK: Reading

    func testTheMatrixOfAFile() {
        let imported = ConvDocument.make(from: ConvConfig.parse(sample).config)
        XCTAssertTrue(imported.issues.isEmpty)
        let d = imported.document
        XCTAssertEqual(d.inputCount, 2)
        XCTAssertEqual(d.outputCount, 2)
        XCTAssertEqual(d.client, "chapel")
        XCTAssertNil(d.server)
        XCTAssertEqual(d.partition, 256)
        XCTAssertEqual(d.maxLength, 115200)
        XCTAssertEqual(d.inputs[0], ConvPortSpec(name: "In L", connection: "system:capture_1"))
        XCTAssertEqual(d.inputs[1], ConvPortSpec())
        XCTAssertEqual(d.outputs[1], ConvPortSpec(name: "Out.R", connection: nil))
        XCTAssertEqual(d.content.preamble, ["# reverb of a chapel", "# two by two", ""])
    }

    func testImpulsesAreOnTheirPairsFromZero() {
        let d = document(sample)
        XCTAssertEqual(d.impulses(at: pair(0, 0)).count, 1)
        XCTAssertEqual(d.impulses(at: pair(1, 1)).first?.source, .file(path: "chapel.wav", channel: 2))
        let cut = d.impulses(at: pair(0, 1)).first
        XCTAssertEqual(cut?.offset, 100)
        XCTAssertEqual(cut?.length, 5000)
        XCTAssertEqual(cut?.directory, "/Users/eric/IR")
        XCTAssertEqual(d.impulses(at: pair(1, 0)).map(\.source), [.dirac, .copy(of: pair(0, 0))])
        XCTAssertEqual(d.impulses(at: pair(1, 0)).first?.delay, 10)
    }

    func testSeveralImpulsesOnTheSamePairAreKeptInOrder() {
        let d = document("/convolver/new 1 1 64 256\n/impulse/dirac 1 1 1 0\n/impulse/dirac 1 1 0.5 5\n/impulse/hilbert 1 1 1 64 128\n")
        XCTAssertEqual(d.impulses(at: pair(0, 0)).map(\.source), [.dirac, .dirac, .hilbert(length: 128)])
    }

    func testWhatDoesNotFitIsReported() {
        let issues = ConvDocument.make(from: ConvConfig.parse("""
        /convolver/new 1 1 64 256
        /input/name 3 Far
        /impulse/dirac 2 1 1 0
        /impulse/copy 1 1 5 5
        """).config).issues
        XCTAssertEqual(issues.map(\.line), [2, 3, 4])
    }

    func testGainIsLinearInTheFileAndInDecibelsOnRequest() {
        var i = ConvImpulse(source: .dirac, gain: 0.5)
        XCTAssertEqual(i.gainDB, -6.0206, accuracy: 1e-3)
        i.gainDB = -20
        XCTAssertEqual(i.gain, 0.1, accuracy: 1e-12)
        XCTAssertEqual(ConvImpulse(source: .dirac, gain: 0).gainDB, -.infinity)
    }

    // MARK: Writing

    func testAnUntouchedDocumentComesOutAsTheFileWas() {
        let d = document(sample)
        XCTAssertFalse(d.isModified)
        XCTAssertEqual(d.makeConfig(automatic: automatic).text, sample)
    }

    func testAChangedDocumentIsWrittenAgainInARegularOrder() {
        var d = document(sample)
        d.content.impulses[pair(0, 0)]?[0].gain = 0.75
        XCTAssertTrue(d.isModified)
        let text = d.makeConfig(automatic: automatic).text
        XCTAssertEqual(text, """
        # reverb of a chapel
        # two by two

        /jack/client chapel
        /convolver/new 2 2 256 115200 1
        /input/name 1 "In L" system:capture_1
        /output/name 2 Out.R
        /impulse/dirac 2 1 1 10
        /cd /Users/eric/IR
        /impulse/read 1 1 0.75 0 0 0 1 chapel.wav
        /impulse/read 1 2 0.25 0 100 5000 2 chapel.wav
        /impulse/read 2 2 0.5 0 0 0 2 chapel.wav
        /impulse/copy 2 1 1 1

        """)
    }

    func testTheEditedFileMeansTheSameWhenItIsReadAgain() {
        var d = document(sample)
        d.add(ConvImpulse(source: .hilbert(length: 512), gain: 1, delay: 256), at: pair(0, 0))
        let again = document(d.makeConfig(automatic: automatic).text)
        // The impulse responses of a pair are added: the order in which they are written does not matter.
        func described(_ document: ConvDocument) -> [ConvPair: [String]] {
            document.content.impulses.mapValues { $0.map { "\($0)" }.sorted() }
        }
        XCTAssertEqual(described(again), described(d))
        XCTAssertEqual(again.content.inputs, d.content.inputs)
        XCTAssertEqual(again.content.outputs, d.content.outputs)
    }

    func testFilesOfTheFolderOfTheConfigurationComeBeforeAnyCd() {
        var d = ConvDocument(inputs: 1, outputs: 2)
        d.add(ConvImpulse(source: .file(path: "far.wav", channel: 1), directory: "/far"), at: pair(0, 0))
        d.add(ConvImpulse(source: .file(path: "near.wav", channel: 1), directory: nil), at: pair(0, 1))
        let lines = d.makeConfig(automatic: automatic).lines.map(\.text)
        XCTAssertEqual(Array(lines.suffix(3)), ["/impulse/read 1 2 1 0 0 0 1 near.wav", "/cd /far", "/impulse/read 1 1 1 0 0 0 1 far.wav"])
    }

    func testTheNumbersOfTheHeaderAreTheOnesSetByHandOrTheAutomaticOnes() {
        var d = ConvDocument(inputs: 2, outputs: 2)
        d.add(ConvImpulse(source: .dirac), at: pair(0, 0))
        XCTAssertEqual(d.makeConfig(automatic: automatic).convolver?.partition, 256)
        XCTAssertEqual(d.makeConfig(automatic: automatic).convolver?.maxLength, 4096)
        XCTAssertEqual(d.makeConfig(automatic: automatic).convolver?.density, 0.5)
        d.partition = 512
        d.maxLength = 9999
        let c = d.makeConfig(automatic: automatic).convolver
        XCTAssertEqual(c?.partition, 512)
        XCTAssertEqual(c?.maxLength, 9999)
    }

    func testOnlyThePortsThatAreCustomAreWritten() {
        var d = ConvDocument(inputs: 3, outputs: 1)
        d.inputs[1] = ConvPortSpec(name: "Mic")
        d.outputs[0] = ConvPortSpec(connection: "system:playback_1")   // a connection without a name still needs one
        let text = d.makeConfig(automatic: automatic).text
        XCTAssertTrue(text.contains("/input/name 2 Mic\n"))
        XCTAssertFalse(text.contains("/input/name 1"))
        XCTAssertTrue(text.contains("/output/name 1 out-1 system:playback_1\n"))
    }

    // MARK: Editing

    func testAddReplaceRemoveClear() {
        var d = ConvDocument(inputs: 2, outputs: 2)
        d.add(ConvImpulse(source: .dirac), at: pair(0, 1))
        d.add(ConvImpulse(source: .dirac, delay: 5), at: pair(0, 1))
        d.replace(ConvImpulse(source: .dirac, delay: 9), at: 1, of: pair(0, 1))
        XCTAssertEqual(d.impulses(at: pair(0, 1)).map(\.delay), [0, 9])
        d.remove(at: 0, of: pair(0, 1))
        XCTAssertEqual(d.impulses(at: pair(0, 1)).map(\.delay), [9])
        d.remove(at: 0, of: pair(0, 1))
        XCTAssertTrue(d.impulses(at: pair(0, 1)).isEmpty)
        XCTAssertEqual(d.placedPairs, 0)
        d.add(ConvImpulse(source: .dirac), at: pair(1, 1))
        d.clear(pair(1, 1))
        XCTAssertEqual(d.placedPairs, 0)
    }

    func testNothingIsPlacedOutsideTheMatrix() {
        var d = ConvDocument(inputs: 1, outputs: 1)
        d.add(ConvImpulse(source: .dirac), at: pair(1, 0))
        d.add(ConvImpulse(source: .dirac), at: pair(0, -1))
        XCTAssertEqual(d.placedPairs, 0)
    }

    func testResizingDropsWhatGoesAway() {
        var d = document(sample)
        d.resize(inputs: 1, outputs: 2)
        XCTAssertEqual(d.inputCount, 1)
        XCTAssertEqual(d.inputs[0].name, "In L")
        XCTAssertTrue(d.impulses(at: pair(1, 0)).isEmpty)
        XCTAssertEqual(d.impulses(at: pair(0, 1)).count, 1)
        d.resize(inputs: 3, outputs: 2)
        XCTAssertEqual(d.inputs[2], ConvPortSpec())
    }

    func testACopyOfAPairThatWentAwayGoesToo() {
        var d = ConvDocument(inputs: 2, outputs: 2)
        d.add(ConvImpulse(source: .dirac), at: pair(1, 1))
        d.add(ConvImpulse(source: .copy(of: pair(1, 1))), at: pair(0, 0))
        d.resize(inputs: 1, outputs: 2)
        XCTAssertEqual(d.placedPairs, 0)
    }

    // MARK: What it says

    func testDensityAndAutomaticHeader() {
        var d = ConvDocument(inputs: 2, outputs: 4)
        d.add(ConvImpulse(source: .file(path: "a.wav", channel: 1), delay: 10), at: pair(0, 0))
        d.add(ConvImpulse(source: .file(path: "a.wav", channel: 1), delay: 0, offset: 100, length: 0), at: pair(1, 3))
        d.add(ConvImpulse(source: .dirac, delay: 5), at: pair(0, 1))
        XCTAssertEqual(d.pairDensity, 3.0 / 8.0, accuracy: 1e-12)
        let h = d.automaticHeader(period: 128) { impulse in
            if case .file(let path, _) = impulse.source, path == "a.wav" { return 1000 }
            return nil
        }
        XCTAssertEqual(h.partition, 128)
        XCTAssertEqual(h.maxLength, 1010)      // the first file: delay 10 + 1000 frames
        XCTAssertEqual(h.density, 0.38)
    }

    func testTheLongestImpulseCountsCutsHilbertFiltersAndCopies() {
        var d = ConvDocument(inputs: 2, outputs: 2)
        d.add(ConvImpulse(source: .file(path: "a.wav", channel: 1), delay: 100, offset: 0, length: 300), at: pair(0, 0))
        d.add(ConvImpulse(source: .hilbert(length: 1024), delay: 512), at: pair(0, 1))
        d.add(ConvImpulse(source: .copy(of: pair(0, 0))), at: pair(1, 1))
        XCTAssertEqual(d.longestImpulse { _ in nil }, 1024)   // 512 + 1024 / 2
        d.add(ConvImpulse(source: .file(path: "b.wav", channel: 1), delay: 0, offset: 0, length: 5000), at: pair(1, 0))
        XCTAssertEqual(d.longestImpulse { _ in nil }, 5000)
        XCTAssertEqual(ConvDocument(inputs: 1, outputs: 1).longestImpulse { _ in nil }, 0)
    }

    // MARK: The examples of the author

    func testEveryExampleSurvivesBeingEditedAndWrittenAgain() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        guard let walker = FileManager.default.enumerator(at: root.appendingPathComponent("upstream/config-files"), includingPropertiesForKeys: nil) else {
            throw XCTSkip("the examples are not there")
        }
        let files = walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "conf" }
        XCTAssertGreaterThan(files.count, 20)
        for url in files {
            let text = String(decoding: try Data(contentsOf: url), as: UTF8.self)
            let imported = ConvDocument.make(from: ConvConfig.parse(text).config)
            XCTAssertTrue(imported.issues.isEmpty, "\(url.lastPathComponent): \(imported.issues)")
            var d = imported.document
            XCTAssertEqual(d.makeConfig(automatic: automatic).text, text, url.lastPathComponent)

            // Touch it: the whole file is then written again from the matrix.
            d.content.client = (d.content.client ?? "jconvolver")
            XCTAssertTrue(d.isModified)
            let written = d.makeConfig(automatic: automatic).text
            let back = ConvDocument.make(from: ConvConfig.parse(written).config)
            XCTAssertTrue(back.issues.isEmpty, "\(url.lastPathComponent): \(back.issues)")
            XCTAssertEqual(back.document.inputCount, d.inputCount, url.lastPathComponent)
            XCTAssertEqual(back.document.outputCount, d.outputCount, url.lastPathComponent)
            XCTAssertEqual(back.document.content.impulses.keys.sorted(), d.content.impulses.keys.sorted(), url.lastPathComponent)
            for key in d.content.impulses.keys {
                let a = d.content.impulses[key] ?? [], b = back.document.content.impulses[key] ?? []
                XCTAssertEqual(a.count, b.count, "\(url.lastPathComponent) \(key)")
                // Written files first, then pulses, then copies: the order inside a pair may change, what is there does not.
                XCTAssertEqual(a.map { "\($0.source)" }.sorted(), b.map { "\($0.source)" }.sorted(), "\(url.lastPathComponent) \(key)")
            }
            // And writing it a second time, after a change that changes nothing, gives the same text.
            var again = back.document
            again.content.impulses = back.document.content.impulses
            XCTAssertEqual(again.makeConfig(automatic: automatic).text, written, url.lastPathComponent)
        }
    }
}
