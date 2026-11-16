// SPDX-License-Identifier: MIT

import Foundation

/// Reads a whole source and returns its peaks. It blocks until the file has been read: call it away from the main
/// actor (`WaveformModel` does).
///
/// A big file, or one with many channels, is cut into parts of whole columns. Each part is read and measured by a
/// thread of its own with a source of its own, and the parts are joined at the end: the result is exactly the one of a
/// single pass.
public enum WaveformLoader {
    public struct Cancelled: Error {}

    /// Samples (frames times channels) under which one thread is enough: starting more would cost more than it saves.
    static let samplesPerWorker: Int64 = 8_000_000

    /// How many threads read a file of that size: one per 8 million samples, up to the number of cores, and at most 8.
    public static func automaticWorkers(frames: Int64, channels: Int) -> Int {
        let byWork = Int(max(frames, 0) * Int64(max(channels, 1)) / samplesPerWorker)
        return max(1, min(byWork, ProcessInfo.processInfo.activeProcessorCount, 8))
    }

    /// Reads one source, from the start to the end, with one thread.
    public static func peaks(from source: SampleSource,
                             columns: Int = 4096,
                             blockFrames: Int = 1 << 15,
                             isCancelled: () -> Bool = { false },
                             progressInterval: TimeInterval = 0.1,
                             progress: ((WaveformPeaks) -> Void)? = nil) throws -> WaveformPeaks {
        try peaks(makeSource: { source }, workers: 1, columns: columns, blockFrames: blockFrames,
                  isCancelled: isCancelled, progressInterval: progressInterval, progress: progress)
    }

    /// - Parameters:
    ///   - makeSource: opens the file. It is called once for each thread (the first source is used for the first part),
    ///     so that each part has its own position in the file.
    ///   - workers: threads to read with; nil lets the loader decide from the size of the file. Use 1 for a disk that
    ///     does not like several readings at once (a network, a hard disk).
    ///   - columns: columns of the peaks (4096 is enough for any screen).
    ///   - blockFrames: frames read at a time.
    ///   - isCancelled: asked every `progressInterval` or so, from the calling thread; when it answers true the
    ///     loader stops the threads and throws `Cancelled`.
    ///   - progressInterval: at most one `progress` call per interval, from the calling thread, with the peaks read so
    ///     far. While several parts are read at once, those peaks have gaps: see `WaveformPeaks.columnsRead`.
    public static func peaks(makeSource: @escaping @Sendable () throws -> any SampleSource,
                             workers: Int? = nil,
                             columns: Int = 4096,
                             blockFrames: Int = 1 << 15,
                             isCancelled: () -> Bool = { false },
                             progressInterval: TimeInterval = 0.1,
                             progress: ((WaveformPeaks) -> Void)? = nil) throws -> WaveformPeaks {
        let first = try makeSource()
        let geometry = PeakAccumulator(channels: first.channels, totalFrames: first.frames, sampleRate: first.sampleRate, columns: columns)
        let wanted = workers ?? automaticWorkers(frames: first.frames, channels: first.channels)
        let count = max(1, min(wanted, geometry.columns))
        let state = Shared(geometry: geometry, parts: count)
        let group = DispatchGroup()
        let factory: @Sendable () throws -> any SampleSource = { try makeSource() }

        for k in 0..<count {
            // Whole columns for each part, so that no column is shared by two threads.
            let startColumn = k * geometry.columns / count, endColumn = (k + 1) * geometry.columns / count
            let start = Int64(startColumn) * geometry.framesPerColumn
            let end: Int64 = k == count - 1 ? .max : Int64(endColumn) * geometry.framesPerColumn
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                defer { group.leave() }
                do {
                    let source = k == 0 ? first : try factory()
                    try readPart(of: source, part: k, from: start, to: end, geometry: geometry, blockFrames: blockFrames, state: state)
                } catch {
                    state.fail(error)
                }
            }
        }

        let interval = max(progressInterval, 0.005)
        while group.wait(timeout: .now() + interval) == .timedOut {
            if isCancelled() { state.stop() }
            progress?(state.merged())
        }
        if isCancelled() { state.stop(); throw Cancelled() }
        if let error = state.error { throw error }
        return state.merged()
    }

    private static func readPart(of source: SampleSource, part: Int, from start: Int64, to end: Int64,
                                 geometry: PeakAccumulator, blockFrames: Int, state: Shared) throws {
        var accumulator = PeakAccumulator(like: geometry, startFrame: start)
        if start > 0 { try source.seek(toFrame: start) }
        let channels = geometry.channels
        let buffer = UnsafeMutablePointer<Float>.allocate(capacity: blockFrames * channels)
        defer { buffer.deallocate() }
        let clock = ContinuousClock()
        var lastStore = clock.now
        var position = start
        while !state.isStopped {
            let room = end == .max ? blockFrames : Int(min(Int64(blockFrames), end - position))
            if room <= 0 { break }
            let got = try source.read(into: buffer, maxFrames: room)
            if got == 0 { break }
            accumulator.add(interleaved: buffer, frames: got)
            position += Int64(got)
            if clock.now - lastStore >= .milliseconds(50) {
                lastStore = clock.now
                state.store(accumulator, part: part)
            }
        }
        state.store(accumulator, part: part)
    }

    /// What the threads share: the latest state of each part, whether to stop, and the first error.
    private final class Shared: @unchecked Sendable {
        private let lock = NSLock()
        private var slots: [PeakAccumulator?]
        private let geometry: PeakAccumulator
        private var stopped = false
        private(set) var error: Error?

        init(geometry: PeakAccumulator, parts: Int) {
            self.geometry = geometry
            slots = Array(repeating: nil, count: parts)
        }

        var isStopped: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
        func stop() { lock.lock(); stopped = true; lock.unlock() }
        func fail(_ e: Error) { lock.lock(); if error == nil { error = e }; stopped = true; lock.unlock() }
        func store(_ accumulator: PeakAccumulator, part: Int) { lock.lock(); slots[part] = accumulator; lock.unlock() }

        func merged() -> WaveformPeaks {
            lock.lock()
            let parts = slots.compactMap { $0 }
            lock.unlock()
            return PeakAccumulator.merged([geometry] + parts)
        }
    }
}
