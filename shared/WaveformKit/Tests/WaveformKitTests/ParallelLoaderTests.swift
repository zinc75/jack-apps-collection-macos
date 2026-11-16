// SPDX-License-Identifier: MIT

import XCTest
@testable import WaveformKit

final class ParallelLoaderTests: XCTestCase {
    private func noise(frames: Int, channels: Int, seed: UInt64 = 7) -> [Float] {
        var state = seed
        return (0..<(frames * channels)).map { _ in
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Float(Int64(bitPattern: state >> 11) % 2000) / 1000 - 1
        }
    }

    private func load(_ samples: [Float], channels: Int, workers: Int, columns: Int = 4096, announced: Int64? = nil) throws -> WaveformPeaks {
        try WaveformLoader.peaks(makeSource: { TestSource(channels: channels, samples: samples, announcedFrames: announced) },
                                 workers: workers, columns: columns, blockFrames: 777)
    }

    func testPartsGiveExactlyTheResultOfASinglePass() throws {
        for channels in [1, 2, 9] {
            let samples = noise(frames: 60_000, channels: channels)
            let single = try load(samples, channels: channels, workers: 1, columns: 300)
            for workers in [2, 3, 7, 16] {
                XCTAssertEqual(try load(samples, channels: channels, workers: workers, columns: 300), single, "\(channels) channels, \(workers) workers")
            }
        }
    }

    func testMoreWorkersThanColumnsIsFine() throws {
        let samples = noise(frames: 40, channels: 2)
        XCTAssertEqual(try load(samples, channels: 2, workers: 16), try load(samples, channels: 2, workers: 1))
    }

    func testAFileLongerThanAnnouncedKeepsItsEndInTheLastColumn() throws {
        var samples = noise(frames: 10_000, channels: 1)
        samples[9_999] = 5   // beyond the announced 9 000 frames
        let single = try load(samples, channels: 1, workers: 1, columns: 90, announced: 9_000)
        let parallel = try load(samples, channels: 1, workers: 4, columns: 90, announced: 9_000)
        XCTAssertEqual(parallel, single)
        XCTAssertEqual(parallel.maximums[0].last, 5)
    }

    func testAFileShorterThanAnnouncedIsIncomplete() throws {
        let samples = noise(frames: 5_000, channels: 1)
        let peaks = try load(samples, channels: 1, workers: 3, columns: 50, announced: 10_000)
        XCTAssertFalse(peaks.isComplete)
        XCTAssertEqual(peaks.filledFrames, 5_000)
        XCTAssertEqual(peaks.readColumnCount, 25)
        XCTAssertTrue(peaks.columnsRead[24])
        XCTAssertFalse(peaks.columnsRead[25])
    }

    func testTheProgressGrowsAndEndsAtTheWholeFile() throws {
        let samples = noise(frames: 100_000, channels: 2)
        var reports = [WaveformPeaks]()
        let peaks = try WaveformLoader.peaks(makeSource: { TestSource(channels: 2, samples: samples, delay: 0.001) },
                                             workers: 4, columns: 200, blockFrames: 1000, progressInterval: 0) { reports.append($0) }
        XCTAssertGreaterThan(reports.count, 3)
        XCTAssertEqual(reports.map(\.filledFrames), reports.map(\.filledFrames).sorted())
        XCTAssertTrue(peaks.isComplete)
        XCTAssertEqual(peaks.readColumnCount, peaks.columns)
        // While the parts are read at once, columns far apart are read before the ones between.
        XCTAssertTrue(reports.contains { r in r.columnsRead.first == true && r.columnsRead.contains(false) && r.readColumnCount > r.columns / 8 })
    }

    func testAnErrorInOnePartStopsTheOthersAndIsThrown() {
        let samples = noise(frames: 100_000, channels: 1)
        let made = Counter()
        XCTAssertThrowsError(try WaveformLoader.peaks(makeSource: {
            let n = made.next()
            let s = TestSource(channels: 1, samples: samples, delay: 0.001)
            if n == 3 { s.failAfterReads = 2 }
            return s
        }, workers: 4, columns: 100, blockFrames: 500)) {
            XCTAssertTrue($0 is CocoaError)
        }
    }

    func testCancellingStopsEveryPart() {
        let samples = noise(frames: 400_000, channels: 1)
        let sources = Collected<TestSource>()
        var polls = 0
        XCTAssertThrowsError(try WaveformLoader.peaks(makeSource: {
            let s = TestSource(channels: 1, samples: samples, delay: 0.002)
            sources.add(s)
            return s
        }, workers: 4, columns: 100, blockFrames: 500, isCancelled: { polls += 1; return polls > 2 })) {
            XCTAssertTrue($0 is WaveformLoader.Cancelled)
        }
        let reads = sources.all.map(\.reads)
        Thread.sleep(forTimeInterval: 0.06)
        XCTAssertEqual(sources.all.map(\.reads), reads, "a part went on reading after the cancellation")
    }

    func testTheNumberOfWorkersFollowsTheSizeOfTheFile() {
        XCTAssertEqual(WaveformLoader.automaticWorkers(frames: 48_000 * 60, channels: 2), 1)       // 5.8 M samples
        XCTAssertGreaterThan(WaveformLoader.automaticWorkers(frames: 48_000 * 3600 * 12, channels: 19), 1)
        XCTAssertLessThanOrEqual(WaveformLoader.automaticWorkers(frames: 48_000 * 3600 * 12, channels: 19), 8)
        XCTAssertEqual(WaveformLoader.automaticWorkers(frames: 0, channels: 2), 1)
    }
}
