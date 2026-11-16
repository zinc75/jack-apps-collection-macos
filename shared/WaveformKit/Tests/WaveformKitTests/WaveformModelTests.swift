// SPDX-License-Identifier: MIT

import XCTest
@testable import WaveformKit

@MainActor
final class WaveformModelTests: XCTestCase {
    private struct Failure: Error {}

    private func wait(for model: WaveformModel, until state: WaveformModel.State) async throws {
        for _ in 0..<400 {
            if model.state == state { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("the model stayed \(model.state), not \(state)")
    }

    func testTheModelFillsItsPeaks() async throws {
        let model = WaveformModel()
        XCTAssertEqual(model.state, .idle)
        let samples = (0..<50_000).map { Float($0 % 100) / 100 }
        model.load(columns: 200) { MemorySampleSource(channels: 1, sampleRate: 48000, samples: samples) }
        XCTAssertEqual(model.state, .loading)
        XCTAssertNil(model.finishedPeaks)
        try await wait(for: model, until: .ready)
        XCTAssertEqual(model.peaks?.isComplete, true)
        XCTAssertEqual(model.finishedPeaks, model.peaks)
        XCTAssertEqual(model.peaks?.columns, 200)
        XCTAssertEqual(model.progress, 1)
    }

    func testASourceThatCannotBeOpenedFails() async throws {
        let model = WaveformModel()
        model.load { throw Failure() }
        try await wait(for: model, until: .failed)
        XCTAssertNil(model.peaks)
    }

    func testALoadReplacesThePreviousOne() async throws {
        let model = WaveformModel()
        model.load(columns: 50) { MemorySampleSource(channels: 1, sampleRate: 48000, samples: [Float](repeating: 0.9, count: 500_000)) }
        model.load(columns: 50) { MemorySampleSource(channels: 2, sampleRate: 44100, samples: [Float](repeating: 0.1, count: 2000)) }
        try await wait(for: model, until: .ready)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(model.peaks?.channels, 2)
        XCTAssertEqual(model.peaks?.sampleRate, 44100)
    }

    func testCancellingLeavesNothingToShowForAnUnfinishedLoad() async throws {
        let model = WaveformModel()
        model.load(columns: 50) { MemorySampleSource(channels: 1, sampleRate: 48000, samples: [Float](repeating: 0.5, count: 5_000_000)) }
        model.cancel()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNotEqual(model.state, .ready)
    }
}
