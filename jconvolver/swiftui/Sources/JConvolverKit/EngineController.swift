// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Observation

/// Runs the program, and keeps what the interface shows about it: its state, its journal, its load and the audio cuts.
///
/// One run at a time. The state says how a run ended: the exit code alone does not tell (jconvolver ends with 0 after
/// "CPU overload, exiting."), so `.ended` carries the outcome worked out from what the program said.
@MainActor
@Observable
public final class EngineController {
    public enum State: Equatable, Sendable {
        case idle
        case running
        /// Asked to end, not ended yet.
        case stopping
        case ended(EngineTermination)
    }

    public private(set) var state: State = .idle
    public private(set) var log = EngineLog()
    /// The command of the current or last run.
    public private(set) var command: EngineCommand?
    /// The processor the program used over the last second, in cores; nil before the first reading and when it is not running.
    public private(set) var cores: Double?
    /// The audio cuts that JACK reported since the start of the run.
    public private(set) var xruns = 0
    /// The name JACK gave the client of the program in this run, when the program said it (nil before, and with a program that does not).
    public private(set) var clientName: String?
    public private(set) var startedAt: Date?
    /// When the last run ended, and how long it ran (nil while it runs or before the first one).
    public private(set) var endedAt: Date?
    public var runSeconds: Double? {
        guard case .ended = state, let startedAt, let endedAt else { return nil }
        return endedAt.timeIntervalSince(startedAt)
    }

    /// The seconds between two readings of the load.
    @ObservationIgnored public var sampleInterval: TimeInterval = 1

    @ObservationIgnored private var process: EngineProcess?
    @ObservationIgnored private var sampler: EngineLoadSampler?
    @ObservationIgnored private var sampling: Task<Void, Never>?

    public init() {}

    public var isRunning: Bool { state == .running || state == .stopping }

    /// What the program takes of the whole machine, from 0 to 1.
    public var machineShare: Double? { cores.map { EngineLoad.machineShare(cores: $0) } }

    /// Whether the last run ended because the program stopped on its own with a reason, or with an error.
    public var endedOnAProblem: Bool {
        guard case .ended(let t) = state else { return false }
        switch t.outcome {
        case .stoppedByEngine, .failed: return true
        case .finished, .stoppedOnRequest: return false
        }
    }

    // MARK: Running

    /// Starts the program. Does nothing while one is running.
    /// - Throws: `EngineProcess.LaunchError`, after having written it in the journal.
    public func start(_ command: EngineCommand, executable: URL, environment: [String: String]? = nil) throws {
        guard !isRunning else { return }
        let process = EngineProcess(executable: executable, command: command, environment: environment)
        process.onEvent = { [weak self] event in self?.handle(event) }
        self.command = command
        xruns = 0
        clientName = nil
        cores = nil
        log.append(note: .launch(commandLine: command.displayString), startsRun: true)
        do {
            try process.start()
        } catch {
            log.append(note: .cannotLaunch(reason: Self.describe(error)), severity: .error)
            throw error
        }
        self.process = process
        startedAt = Date()
        state = .running
        sampler = process.processIdentifier.map { EngineLoadSampler(pid: $0) }
        startSampling()
    }

    /// The process of the program while it runs.
    public var processID: pid_t? {
        guard state == .running, let id = process?.processIdentifier, id > 0 else { return nil }
        return id
    }

    /// Asks the program to end.
    public func stop() {
        guard state == .running else { return }
        state = .stopping
        log.append(note: .stopRequested)
        process?.stop()
    }

    /// JACK reported an audio cut, with how late the cycle was when that is known.
    public func recordXrun(microseconds: Int? = nil) {
        guard isRunning else { return }
        xruns += 1
        log.append(note: .xrun(microseconds: microseconds), source: .jack, severity: .warning)
    }

    /// Forgets the last run: the state goes back to idle, the journal is kept.
    public func acknowledgeEnd() {
        if case .ended = state { state = .idle }
    }

    public func clearLog() { log.clear() }

    // MARK: Inside

    private func handle(_ event: EngineEvent) {
        switch event {
        case .message(let message):
            if case .clientName(let name) = message.kind { clientName = name }
            log.append(message)
        case .ended(let termination):
            stopSampling()
            cores = nil
            log.append(note: .ended(program: command?.program.rawValue ?? "", status: termination.status),
                       severity: termination.outcome == .finished || termination.outcome == .stoppedOnRequest ? .info : .error)
            process = nil
            endedAt = Date()
            state = .ended(termination)
        }
    }

    private func startSampling() {
        sampling?.cancel()
        sampling = Task { [weak self] in
            while !Task.isCancelled {
                let interval = self?.sampleInterval ?? 1
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled, let self else { return }
                if let reading = self.sampler?.sample() { self.cores = reading }
            }
        }
    }

    private func stopSampling() {
        sampling?.cancel()
        sampling = nil
        sampler = nil
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case EngineProcess.LaunchError.executableNotFound: return "program not found"
        case EngineProcess.LaunchError.cannotStart(let reason): return reason
        default: return error.localizedDescription
        }
    }
}
