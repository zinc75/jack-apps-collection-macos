// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import JConvolverKit

final class PathResolverTests: XCTestCase {
    private func document(_ files: [(file: String, directory: String?)]) -> ConvDocument {
        var d = ConvDocument(inputs: 1, outputs: files.count)
        for (i, f) in files.enumerated() {
            d.add(ConvImpulse(source: .file(path: f.file, channel: 1), directory: f.directory), at: ConvPair(input: 0, output: i))
        }
        return d
    }

    private func resolve(_ d: ConvDocument, existing: Set<String>, folders: [String: [String]] = [:]) -> [PathProposal] {
        PathResolver.proposals(for: d, configDirectory: "/work/session", fileExists: { existing.contains($0) }, subfolders: { folders[$0] ?? [] })
    }

    func testFilesNextToTheConfigurationAreFoundWhateverTheOldFolderWas() {
        let d = document([("a.wav", "/Users/bob/IR/hall"), ("b.wav", "/Users/bob/IR/hall")])
        let proposals = resolve(d, existing: ["/work/session/a.wav", "/work/session/b.wav"])
        XCTAssertEqual(proposals.count, 1)
        XCTAssertEqual(proposals[0].from, "/Users/bob/IR/hall")
        XCTAssertTrue(proposals[0].isInConfigurationFolder)
        XCTAssertEqual(proposals[0].found, ["a.wav", "b.wav"])
        XCTAssertEqual(proposals[0].missing, [])
    }

    func testTheEndOfTheOldFolderIsLookedForNextToTheConfiguration() {
        let d = document([("a.wav", "/Users/bob/IR/hall")])
        let proposals = resolve(d, existing: ["/work/session/hall/a.wav"])
        XCTAssertEqual(proposals.first?.to, "hall")
    }

    func testASubfolderOfTheConfigurationIsFound() {
        let d = document([("a.wav", "/Users/bob/elsewhere")])
        let proposals = resolve(d, existing: ["/work/session/impulses/a.wav"], folders: ["/work/session": ["impulses", "other"]])
        XCTAssertEqual(proposals.first?.to, "impulses")
    }

    func testWhatIsStillMissingIsSaid() {
        let d = document([("a.wav", "/old"), ("b.wav", "/old")])
        let proposals = resolve(d, existing: ["/work/session/a.wav"])
        XCTAssertEqual(proposals.first?.found, ["a.wav"])
        XCTAssertEqual(proposals.first?.missing, ["b.wav"])
    }

    func testNothingFoundGivesNoProposal() {
        XCTAssertEqual(resolve(document([("a.wav", "/old")]), existing: []), [])
    }

    func testFilesThatAreThereAreLeftAlone() {
        let d = document([("a.wav", "/old")])
        XCTAssertEqual(resolve(d, existing: ["/old/a.wav", "/work/session/a.wav"]), [])
    }

    func testAnAbsolutePathIsReplacedByAName() {
        var d = document([("/Users/bob/IR/hall/a.wav", nil)])
        let proposals = resolve(d, existing: ["/work/session/a.wav"])
        XCTAssertEqual(proposals.count, 1)
        PathResolver.apply(proposals, to: &d)
        guard case .file(let file, _) = d.impulses(at: ConvPair(input: 0, output: 0))[0].source else { return XCTFail() }
        XCTAssertEqual(file, "a.wav")
    }

    func testApplyingRemovesTheCdAndNamesTheFileFromTheFolderOfTheConfiguration() {
        var d = document([("a.wav", "/Users/bob/IR/hall")])
        PathResolver.apply(resolve(d, existing: ["/work/session/hall/a.wav"]), to: &d)
        let impulse = d.impulses(at: ConvPair(input: 0, output: 0))[0]
        XCTAssertNil(impulse.directory)
        guard case .file(let file, _) = impulse.source else { return XCTFail() }
        XCTAssertEqual(file, "hall/a.wav")
    }
}
