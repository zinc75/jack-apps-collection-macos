// SPDX-License-Identifier: MIT

import Foundation
import Observation

/// What a session is doing, in three words: nothing running, something running (an engine, a recording, a player), something that went wrong.
public enum SessionState: Sendable {
    case idle, active, failed
}

/// A small label with a symbol (the JACK client of an engine, for instance).
public struct SessionBadge: Identifiable, Hashable, Sendable {
    public var id: String { text }
    public var text: String
    public var symbol: String?
    public init(_ text: String, symbol: String? = nil) { self.text = text; self.symbol = symbol }
}

/// A bar with a value from 0 to 1 and the text that says it (the load of an engine).
public struct SessionGauge: Identifiable, Hashable, Sendable {
    public enum Level: Sendable { case normal, warning, alert }
    public var id: String { label }
    public var label: String
    public var value: Double
    public var text: String
    public var level: Level
    public init(_ label: String, value: Double, text: String, level: Level = .normal) {
        self.label = label; self.value = value; self.text = text; self.level = level
    }
}

/// A short line of information that may be an alert (the audio cuts of an engine).
public struct SessionNote: Identifiable, Hashable, Sendable {
    public var id: String { text }
    public var text: String
    public var isAlert: Bool
    public init(_ text: String, isAlert: Bool = false) { self.text = text; self.isAlert = isAlert }
}

/// What a card of the list of sessions shows of one of them.
public struct SessionCard: Sendable {
    public var title: String
    /// Changes that are not saved.
    public var isModified = false
    /// What the session holds, in a line.
    public var subtitle: String
    public var state: SessionState
    /// Said in place of the gauges while nothing runs.
    public var stateText: String
    public var badges: [SessionBadge] = []
    public var gauges: [SessionGauge] = []
    public var notes: [SessionNote] = []

    public init(title: String, isModified: Bool = false, subtitle: String, state: SessionState, stateText: String,
                badges: [SessionBadge] = [], gauges: [SessionGauge] = [], notes: [SessionNote] = []) {
        self.title = title; self.isModified = isModified; self.subtitle = subtitle; self.state = state; self.stateText = stateText
        self.badges = badges; self.gauges = gauges; self.notes = notes
    }
}

/// What the closing of the window of a session leads to.
public enum WindowCloseDecision: Sendable {
    /// The window closes, and what runs goes on without it.
    case keepRunning
    /// The window closes, and what runs is stopped.
    case stop
    /// The window stays.
    case cancel
}

/// What a tool gives to the kit for each of its sessions (a configuration with its engine, a recording, a player). The kit keeps the windows, the menu
/// bar and the Dock; the tool keeps what the session is and does, and the words of its questions.
@MainActor
public protocol HostedSession: AnyObject, Observable {
    var id: UUID { get }
    /// What the list of sessions shows. Read in a view: what it reads is observed.
    var card: SessionCard { get }
    /// Whether something runs (a window is not closed over a session that runs without asking).
    var isActive: Bool { get }
    /// Whether the session can be started and stopped from the list (a configuration without errors, a player with a file).
    var canToggle: Bool { get }
    /// Whether the session can only be started from its window (the processing of a file ends by itself).
    var canStartFromList: Bool { get }
    /// Starts or stops what the session runs.
    func toggle()
    /// The window is about to close: asks what to do (the questions are the tool's: changes not saved, an engine that runs).
    func decisionForClosingWindow() -> WindowCloseDecision
    /// The application is about to quit: asks, and says whether to go on.
    func confirmQuit() -> Bool
    /// Stops what runs now.
    func stopNow()
    /// Stops what runs before quitting; `completion` is called when it is done (a recording that closes its file takes a moment). The default stops now.
    func stopForQuit(completion: @escaping @MainActor () -> Void)
    /// A session without a window is dropped: asks about what is not saved, and says whether to go on.
    func confirmDiscard() -> Bool
}

public extension HostedSession {
    var canStartFromList: Bool { true }
    func stopForQuit(completion: @escaping @MainActor () -> Void) {
        stopNow()
        completion()
    }
}
