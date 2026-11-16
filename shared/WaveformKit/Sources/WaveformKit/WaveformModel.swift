// SPDX-License-Identifier: MIT

import Foundation
import Observation

/// Computes the peaks of a file in the background, and shows them as they come. One model per file shown: call
/// `load` again to change the file (the work in progress for the previous one is stopped).
@MainActor
@Observable
public final class WaveformModel {
    public enum State: Equatable, Sendable { case idle, loading, ready, failed }

    public private(set) var peaks: WaveformPeaks?
    public private(set) var state: State = .idle
    /// The peaks once the whole file has been read, nil before. Show this one: while a big file is read in several parts
    /// at once, `peaks` has gaps.
    public var finishedPeaks: WaveformPeaks? { state == .ready ? peaks : nil }
    /// The part of the file read, from 0 to 1.
    public var progress: Double { peaks?.filledFraction ?? (state == .ready ? 1 : 0) }

    private var task: Task<Void, Never>?
    private var generation = 0

    public init() {}

    /// Starts reading. `makeSource` is called in the background, so that opening a long file does not block; it is
    /// called once for each thread that reads a part of the file. `workers` is the number of threads, nil to let the
    /// loader decide from the size of the file.
    public func load(columns: Int = 4096, workers: Int? = nil, makeSource: @escaping @Sendable () throws -> any SampleSource) {
        task?.cancel()
        generation += 1
        let mine = generation
        peaks = nil
        state = .loading
        task = Task.detached(priority: .utility) { [weak self] in
            do {
                let result = try WaveformLoader.peaks(makeSource: makeSource, workers: workers, columns: columns, isCancelled: { Task.isCancelled }) { partial in
                    Task { @MainActor in self?.publish(partial, generation: mine, final: false) }
                }
                await self?.publish(result, generation: mine, final: true)
            } catch is WaveformLoader.Cancelled {
                // Replaced by another load, or cancelled: nothing to say.
            } catch {
                await self?.fail(generation: mine)
            }
        }
    }

    public func cancel() {
        task?.cancel()
        generation += 1
        state = peaks == nil ? .idle : state
    }

    private func publish(_ result: WaveformPeaks, generation g: Int, final: Bool) {
        guard g == generation else { return }
        // Partial results may arrive late and out of order: never go back, and never after the end.
        if !final {
            guard state == .loading, (peaks?.filledFrames ?? -1) < result.filledFrames else { return }
        }
        peaks = result
        if final { state = .ready }
    }

    private func fail(generation g: Int) {
        guard g == generation else { return }
        state = .failed
    }
}
