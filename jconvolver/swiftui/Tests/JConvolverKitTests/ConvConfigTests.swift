// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import JConvolverKit

final class ConvConfigTests: XCTestCase {
    /// The examples that come with jconvolver (jconvolver/upstream/config-files): 2 400 lines of every command.
    private func examples() throws -> [URL] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory = root.appendingPathComponent("upstream/config-files")
        guard let walker = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            throw XCTSkip("jconvolver/upstream/config-files is not there")
        }
        let files = walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "conf" }.sorted { $0.path < $1.path }
        if files.isEmpty { throw XCTSkip("no example configuration files") }
        return files
    }

    private func parse(_ text: String) -> ConvConfig { ConvConfig.parse(text).config }

    // MARK: Lines

    func testEachCommand() {
        let text = """
        # a comment
        /jack/client jconvolver
        /jack/server  myserver
        /convolver/new 2 4 256 48000 0.5
        /input/name 1 In.L system:capture_1
        /output/name 3 "Out 3"
        /cd "/Users/eric/IR files"
        /impulse/read 1 2 0.5 10 20 300 2 room.wav
        /impulse/dirac 1 1 1 0
        /impulse/hilbert 2 2 1 512 1024
        /impulse/copy 2 1 1 1
        """
        let c = parse(text)
        XCTAssertEqual(c.lines.map(\.kind), [
            .comment("# a comment"),
            .jackClient("jconvolver"),
            .jackServer("myserver"),
            .convolverNew(inputs: 2, outputs: 4, partition: 256, maxLength: 48000, density: 0.5),
            .inputName(number: 1, name: "In.L", connections: ["system:capture_1"]),
            .outputName(number: 3, name: "Out 3", connections: []),
            .changeDirectory("/Users/eric/IR files"),
            .read(.init(input: 1, output: 2, gain: 0.5, delay: 10, offset: 20, length: 300, channel: 2, file: "room.wav")),
            .dirac(input: 1, output: 1, gain: 1, delay: 0),
            .hilbert(input: 2, output: 2, gain: 1, delay: 512, length: 1024),
            .copy(input: 2, output: 1, fromInput: 1, fromOutput: 1),
        ])
        XCTAssertEqual(c.text, text)
    }

    func testDensityIsOptional() {
        XCTAssertEqual(parse("/convolver/new 1 1 64 4096").convolver?.density, nil)
        XCTAssertEqual(parse("/convolver/new 1 1 64 4096 0.25").convolver?.density, 0.25)
    }

    func testBlankAndIndentedLines() {
        let c = parse("\n   \n   # indented comment\n")
        XCTAssertEqual(c.lines.map(\.kind), [.blank, .blank, .comment("   # indented comment")])
    }

    func testTheEndOfTheFileIsKept() {
        XCTAssertEqual(parse("/cd /a\n").text, "/cd /a\n")
        XCTAssertEqual(parse("/cd /a").text, "/cd /a")
        XCTAssertEqual(parse("/cd /a\n\n").text, "/cd /a\n\n")
        XCTAssertEqual(parse("").text, "")
    }

    func testWindowsLineBreaksComeOutAsTheyWere() {
        let text = "/cd /a\r\n/impulse/dirac 1 1 1 0\r\n"
        let c = parse(text)
        XCTAssertEqual(c.text, text)
        XCTAssertEqual(c.lines.map(\.kind), [.changeDirectory("/a"), .dirac(input: 1, output: 1, gain: 1, delay: 0)])
    }

    // MARK: What the program would refuse

    func testIssuesUseTheWordsOfTheProgram() {
        let (c, issues) = ConvConfig.parse("""
        /convolver/new 2 2 256
        /unknown/command 1
        some words
        /impulse/dirac 1 1
        /cd
        """)
        XCTAssertEqual(issues, [
            ConfIssue(line: 1, message: "Bad or missing parameters."),
            ConfIssue(line: 2, message: "Unknown command."),
            ConfIssue(line: 3, message: "Syntax error."),
            ConfIssue(line: 4, message: "Bad or missing parameters."),
            ConfIssue(line: 5, message: "Bad or missing parameters."),
        ])
        // What is refused is kept as it was written.
        XCTAssertEqual(c.lines[1].kind, .invalid("/unknown/command 1"))
        XCTAssertEqual(c.lines[2].kind, .invalid("some words"))
    }

    func testNegativeAndGarbledNumbersAreRefused() {
        XCTAssertEqual(ConvConfig.parse("/impulse/dirac -1 1 1 0").issues.count, 1)
        XCTAssertEqual(ConvConfig.parse("/impulse/dirac 1x 1 1 0").issues.count, 1)
        XCTAssertEqual(ConvConfig.parse("/impulse/dirac 1 1 abc 0").issues.count, 1)
    }

    // MARK: Writing

    func testAChangedLineIsWrittenAgainAndTheOthersAreNot() {
        var c = parse("# kept as it is   \n/impulse/dirac    1   1  0.5   10\n/cd   /a\n")
        c.lines[1] = ConfLine(.dirac(input: 1, output: 1, gain: 0.25, delay: 20))
        XCTAssertEqual(c.text, "# kept as it is   \n/impulse/dirac 1 1 0.25 20\n/cd   /a\n")
    }

    func testNumbersAreWrittenShortAndExact() {
        XCTAssertEqual(ConfLine.Kind.dirac(input: 1, output: 1, gain: 0.5, delay: 0).formatted, "/impulse/dirac 1 1 0.5 0")
        XCTAssertEqual(ConfLine.Kind.dirac(input: 1, output: 1, gain: 1, delay: 0).formatted, "/impulse/dirac 1 1 1 0")
        let g = 0.31622776601683794   // -10 dB
        let text = ConfLine.Kind.dirac(input: 1, output: 1, gain: g, delay: 0).formatted
        if case .dirac(_, _, let back, _) = ConvConfig.parseLine(text).0 {
            XCTAssertEqual(back, g, accuracy: 1e-9)
        } else { XCTFail("not read back: \(text)") }
    }

    func testNamesAndPathsWithBlanksAreQuoted() {
        XCTAssertEqual(ConfLine.Kind.read(.init(input: 1, output: 1, gain: 1, delay: 0, offset: 0, length: 0, channel: 1, file: "my room.wav")).formatted,
                       "/impulse/read 1 1 1 0 0 0 1 \"my room.wav\"")
        XCTAssertEqual(ConfLine.Kind.outputName(number: 2, name: "Left front", connections: ["system:playback_1"]).formatted,
                       "/output/name 2 \"Left front\" system:playback_1")
    }

    // MARK: What it says

    func testConvolverAndPlacements() {
        let c = parse("""
        /convolver/new 2 2 256 4096
        /impulse/dirac 1 1 1 0
        /cd /ir
        /impulse/read 1 2 1 0 0 0 1 a.wav
        /cd rel
        /impulse/read 2 1 1 0 0 0 1 /abs/b.wav
        """)
        XCTAssertEqual(c.convolver?.inputs, 2)
        XCTAssertEqual(c.convolver?.partition, 256)
        XCTAssertEqual(c.placements.map(\.line), [2, 4, 6])
        XCTAssertEqual(c.placements.map(\.directory), [nil, "/ir", "rel"])
    }

    func testWhereAFileIsLookedFor() {
        XCTAssertEqual(ConvConfig.path(of: "/abs/b.wav", directory: "/ir", configDirectory: "/cfg"), "/abs/b.wav")
        XCTAssertEqual(ConvConfig.path(of: "a.wav", directory: "/ir", configDirectory: "/cfg"), "/ir/a.wav")
        XCTAssertEqual(ConvConfig.path(of: "a.wav", directory: nil, configDirectory: "/cfg"), "/cfg/a.wav")
    }

    // MARK: The examples of the author

    func testEveryExampleIsReadAndComesOutAsItWas() throws {
        var lines = 0
        for url in try examples() {
            let data = try Data(contentsOf: url)
            let text = String(decoding: data, as: UTF8.self)
            let (config, issues) = ConvConfig.parse(text)
            XCTAssertEqual(config.text, text, url.lastPathComponent)
            XCTAssertTrue(issues.isEmpty, "\(url.lastPathComponent): \(issues)")
            XCTAssertNotNil(config.convolver, url.lastPathComponent)
            lines += config.lines.count
        }
        XCTAssertGreaterThan(lines, 2000)
    }

    func testEveryExampleSurvivesBeingWrittenFromItsContent() throws {
        for url in try examples() {
            let text = String(decoding: try Data(contentsOf: url), as: UTF8.self)
            let original = parse(text)
            // Every line written again from what it means, none from the text it was read from.
            let rebuilt = ConvConfig(lines: original.lines.map { ConfLine($0.kind) }, endsWithNewline: original.endsWithNewline)
            let (again, issues) = ConvConfig.parse(rebuilt.text)
            XCTAssertTrue(issues.isEmpty, "\(url.lastPathComponent): \(issues)")
            XCTAssertEqual(again.lines.count, original.lines.count, url.lastPathComponent)
            for (a, b) in zip(original.lines, again.lines) {
                XCTAssertTrue(Self.same(a.kind, b.kind), "\(url.lastPathComponent): \(a.kind) became \(b.kind)")
            }
            // And that second text is a fixed point: nothing more changes.
            XCTAssertEqual(again.text, ConvConfig(lines: again.lines.map { ConfLine($0.kind) }, endsWithNewline: again.endsWithNewline).text, url.lastPathComponent)
        }
    }

    /// The same meaning, the gains and the density being compared as numbers (they are written with 9 digits).
    private static func same(_ a: ConfLine.Kind, _ b: ConfLine.Kind) -> Bool {
        func close(_ x: Double, _ y: Double) -> Bool { abs(x - y) <= 1e-8 * max(1, abs(x)) }
        switch (a, b) {
        case (.read(let r), .read(let s)):
            var r0 = r, s0 = s
            r0.gain = 0; s0.gain = 0
            return close(r.gain, s.gain) && r0 == s0
        case (.dirac(let i, let o, let g, let d), .dirac(let i2, let o2, let g2, let d2)):
            return close(g, g2) && (i, o, d) == (i2, o2, d2)
        case (.hilbert(let i, let o, let g, let d, let l), .hilbert(let i2, let o2, let g2, let d2, let l2)):
            return close(g, g2) && (i, o, d, l) == (i2, o2, d2, l2)
        case (.convolverNew(let i, let o, let p, let m, let d), .convolverNew(let i2, let o2, let p2, let m2, let d2)):
            return (i, o, p, m) == (i2, o2, p2, m2) && (d == nil) == (d2 == nil) && close(d ?? 0, d2 ?? 0)
        default:
            return a == b
        }
    }
}
