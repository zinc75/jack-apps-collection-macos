// SPDX-License-Identifier: MIT

import Foundation
@testable import WaveformKit

/// A source in memory that counts its readings, can be slow, and can announce a length that is not the real one.
final class TestSource: SampleSource, @unchecked Sendable {
    let channels: Int
    let sampleRate: Double = 48000
    private let samples: [Float]
    private let delay: TimeInterval
    private let announced: Int64?
    private let lock = NSLock()
    private var position = 0
    private var count = 0
    var failAfterReads: Int?

    init(channels: Int, samples: [Float], delay: TimeInterval = 0, announcedFrames: Int64? = nil) {
        self.channels = channels
        self.samples = samples
        self.delay = delay
        self.announced = announcedFrames
    }

    var frames: Int64 { announced ?? Int64(samples.count / channels) }
    var reads: Int { lock.lock(); defer { lock.unlock() }; return count }

    func seek(toFrame frame: Int64) throws {
        position = Int(min(max(frame, 0), Int64(samples.count / channels)))
    }

    func read(into buffer: UnsafeMutablePointer<Float>, maxFrames: Int) throws -> Int {
        lock.lock(); count += 1; let n = count; lock.unlock()
        if let failAfterReads, n > failAfterReads { throw CocoaError(.fileReadCorruptFile) }
        if delay > 0 { Thread.sleep(forTimeInterval: delay) }
        let left = samples.count / channels - position
        let got = min(maxFrames, max(left, 0))
        guard got > 0 else { return 0 }
        samples.withUnsafeBufferPointer { buffer.update(from: $0.baseAddress! + position * channels, count: got * channels) }
        position += got
        return got
    }
}

/// A counter several threads can use.
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func next() -> Int { lock.lock(); defer { lock.unlock() }; value += 1; return value }
}

/// A list several threads can add to.
final class Collected<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var items = [T]()
    func add(_ item: T) { lock.lock(); items.append(item); lock.unlock() }
    var all: [T] { lock.lock(); defer { lock.unlock() }; return items }
}
