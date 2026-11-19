// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Observation

/// Where a direction of the link is. The sender cannot know more than "it runs": the protocol is one way.
public enum LinkState: Equatable, Sendable {
    case stopped
    /// The receiver listens and has not heard the sender yet, or waits to start again.
    case waiting
    /// The sender was heard: the receiver adjusts its buffer and its resampler.
    case syncing
    /// The audio flows (for the sender: the program runs).
    case linked
    /// The program could not run, or ended by itself. The text is what it said.
    case failed(String)

    public var isRunning: Bool {
        switch self {
        case .waiting, .syncing, .linked: true
        case .stopped, .failed: false
        }
    }
}

/// The sender that the receiver hears.
public struct SenderInfo: Equatable, Sendable {
    public var address: String
    public var channels: Int
    public var rate: Int
}

/// The receiving direction: runs `zita-n2j`, follows its state and keeps the buffer margin.
@MainActor
@Observable
public final class ReceiverModel {
    /// How many margin values the history keeps: four a second, for a minute.
    public static let historyLength = 240

    public var settings: ReceiveSettings
    public private(set) var state = LinkState.stopped
    public private(set) var sender: SenderInfo?
    /// The length of the resampler filter in use, in samples.
    public private(set) var filterDelay: Int?
    public private(set) var statistics: LinkStatistics?
    /// The buffer margin in milliseconds, the latest one and the last minute of them.
    public private(set) var margin: Double?
    public private(set) var marginHistory = [Double]()
    /// How many times the sound was cut: the queue ran dry, or the loop gave up and started again.
    public private(set) var interruptions = 0
    /// While the receiver waits to start again: the seconds it waits.
    public private(set) var retryDelay: Double?
    /// The latest warnings and other lines of the program.
    public private(set) var log = [String]()
    /// The settings the running program was started with; nil when it does not run.
    public private(set) var runningSettings: ReceiveSettings?

    private let executable: URL?
    private let jackServer: String?
    private var process: LinkProcess?
    private var dry = false

    /// - Parameters:
    ///   - executable: `zita-n2j`; nil when it is not found.
    ///   - jackServer: the name of the JACK server (`--jserv`); nil for the default one.
    public init(settings: ReceiveSettings = ReceiveSettings(), executable: URL?, jackServer: String? = nil) {
        self.settings = settings
        self.executable = executable
        self.jackServer = jackServer
    }

    public var command: BridgeCommand { BridgeCommand(receiver: settings, jackServer: jackServer) }
    public var canStart: Bool { settings.issues.isEmpty && !state.isRunning }
    /// Settings were changed since the program started: it has to be restarted for them to apply.
    public var needsRestart: Bool { runningSettings != nil && runningSettings != settings }

    public func start() {
        guard canStart else { return }
        guard let executable else { state = .failed("zita-n2j was not found"); return }
        reset()
        let link = LinkProcess(executable: executable, command: command)
        link.onEvent = { [weak self] in self?.handle($0) }
        do {
            try link.start()
            process = link; runningSettings = settings; state = .waiting
        } catch {
            state = .failed("\(error)")
        }
    }

    public func stop() { process?.stop() }

    public func resetInterruptions() { interruptions = 0 }

    private func reset() {
        sender = nil; filterDelay = nil; statistics = nil; margin = nil; marginHistory = []
        interruptions = 0; retryDelay = nil; log = []; dry = false
    }

    /// What the program said. Internal so that tests can tell it directly.
    func handle(_ event: LinkEvent) {
        switch event {
        case .waitingForSender:
            state = .waiting
        case .senderFound(let address, let channels, let rate):
            sender = SenderInfo(address: address, channels: channels, rate: rate)
        case .filterDelay(let n):
            filterDelay = n
        case .syncing:
            state = .syncing; retryDelay = nil
        case .receiving:
            state = .linked; retryDelay = nil
        case .retrying(let seconds):
            if state == .linked || state == .syncing { interruptions += 1 }
            state = .waiting; retryDelay = seconds; dry = false
        case .transmitterEnded:
            state = .waiting; sender = nil
        case .fatal:
            state = .failed("Fatal error")
        case .statistics(let s):
            statistics = s
            guard let rate = sender?.rate else { return }
            let m = s.margin(senderRate: Double(rate))
            margin = m
            marginHistory.append(m)
            if marginHistory.count > Self.historyLength { marginHistory.removeFirst(marginHistory.count - Self.historyLength) }
            // A run of lines with a dry queue is one interruption, counted when it begins.
            if s.frames < 0 { if !dry { interruptions += 1 }; dry = true } else { dry = false }
        case .error(let text):
            state = .failed(text); keep(text)
        case .warning(let text), .message(let text):
            keep(text)
        case .exited(let status, let requested):
            process = nil; runningSettings = nil; margin = nil; retryDelay = nil
            if requested { state = .stopped }
            else if case .failed = state { /* the reason is already known */ }
            else { state = status == 0 ? .stopped : .failed("zita-n2j ended with status \(status)") }
        }
    }

    private func keep(_ text: String) {
        log.append(text)
        if log.count > 50 { log.removeFirst(log.count - 50) }
    }
}

/// The sending direction: runs `zita-j2n`.
@MainActor
@Observable
public final class SenderModel {
    public var settings: SendSettings
    public private(set) var state = LinkState.stopped
    public private(set) var log = [String]()
    public private(set) var runningSettings: SendSettings?

    private let executable: URL?
    private let jackServer: String?
    private var process: LinkProcess?

    public init(settings: SendSettings = SendSettings(), executable: URL?, jackServer: String? = nil) {
        self.settings = settings
        self.executable = executable
        self.jackServer = jackServer
    }

    public var command: BridgeCommand { BridgeCommand(sender: settings, jackServer: jackServer) }
    public var canStart: Bool { settings.issues.isEmpty && !state.isRunning }
    public var needsRestart: Bool { runningSettings != nil && runningSettings != settings }

    public func start() {
        guard canStart else { return }
        guard let executable else { state = .failed("zita-j2n was not found"); return }
        log = []
        let link = LinkProcess(executable: executable, command: command)
        link.onEvent = { [weak self] in self?.handle($0) }
        do {
            try link.start()
            // Nothing comes back from the receiver: the sender is "linked" as soon as its program runs.
            process = link; runningSettings = settings; state = .linked
        } catch {
            state = .failed("\(error)")
        }
    }

    public func stop() { process?.stop() }

    func handle(_ event: LinkEvent) {
        switch event {
        case .fatal:
            state = .failed("Fatal error")
        case .error(let text):
            state = .failed(text); keep(text)
        case .warning(let text), .message(let text):
            keep(text)
        case .exited(let status, let requested):
            process = nil; runningSettings = nil
            if requested { state = .stopped }
            else if case .failed = state { /* the reason is already known */ }
            else { state = status == 0 ? .stopped : .failed("zita-j2n ended with status \(status)") }
        default:
            break   // the lines of the receiver do not come from a sender
        }
    }

    private func keep(_ text: String) {
        log.append(text)
        if log.count > 50 { log.removeFirst(log.count - 50) }
    }
}
