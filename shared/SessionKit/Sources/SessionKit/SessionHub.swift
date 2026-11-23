// SPDX-License-Identifier: MIT

import AppKit
import Foundation
import Observation

/// What the application waits for before it quits: the sessions that take a moment to stop.
private final class QuitWaiting {
    var remaining = 0
    var returnedLater = false
    var finishedEarly = false
}

/// How a tool names itself in what the kit shows.
public struct SessionKitConfiguration: Sendable {
    /// The name of the application ("Jack Convolver"): in the title of the window of the sessions and in "Quit".
    public var toolName: String
    /// Whether the icon of the Dock shows the number of sessions that run.
    public var showsDockBadge: Bool
    /// What runs in a session, as a noun, one and several ("moteur", "moteurs"): the list says "2 sessions, 1 moteur en cours d'exécution".
    public var runningNoun: String
    public var runningNounPlural: String

    public init(toolName: String, showsDockBadge: Bool = true, runningNoun: String = "session", runningNounPlural: String = "sessions") {
        self.toolName = toolName
        self.showsDockBadge = showsDockBadge
        self.runningNoun = runningNoun
        self.runningNounPlural = runningNounPlural
    }

    /// The title of the window that lists the sessions: it is how it is found among the windows.
    public var sessionsWindowTitle: String { toolName + " · Sessions" }
}

/// The sessions of an application and what is seen of them: a window for each, which may be closed while what runs goes on, the icon of the menu bar and the
/// Dock that keep them in reach, the window that lists them. The tool makes the sessions; the hub makes them live in windows.
@MainActor
@Observable
public final class SessionHub<S: HostedSession> {
    public let configuration: SessionKitConfiguration
    private let makeSessionWithID: (UUID) -> S
    private let makeIdle: (() -> S)?

    /// The sessions, in the order they were made.
    public private(set) var sessions: [S] = []

    /// What is known of the window of a session.
    private struct WindowState {
        weak var window: NSWindow?
        var shownOnce = false
        var keepsRunning = false
        /// When the window was found: for a moment it is not visible yet, and that is not a window that was hidden.
        var attachedAt = Date.distantPast
        let created = Date()
    }

    @ObservationIgnored private var states: [UUID: WindowState] = [:]
    @ObservationIgnored private var unclaimedID = UUID()
    @ObservationIgnored private var presenceObservers: [NSObjectProtocol] = []

    /// Opens a window on a session; set by a scene, which knows how.
    @ObservationIgnored public var openWindowAction: ((UUID) -> Void)?
    /// Opens the window that lists the sessions.
    @ObservationIgnored public var openSessionsAction: (() -> Void)?

    /// Counts the changes of what is seen of the windows (they are not observable): the menu bar reads it.
    public private(set) var presence = 0

    /// - Parameter makeIdleSession: how to make the session that no window shows (the one that commands act on while no window has the focus); by default
    ///   `makeSession` makes it, which a tool whose first session is special (it reads saved settings) does not want.
    public init(configuration: SessionKitConfiguration, makeSession: @escaping (UUID) -> S, makeIdleSession: (() -> S)? = nil) {
        self.configuration = configuration
        self.makeSessionWithID = makeSession
        self.makeIdle = makeIdleSession
    }

    // MARK: The sessions

    /// A session that no window shows: what the commands of the menus act on while no window has the focus, so that they do nothing. It is not one of the sessions.
    @ObservationIgnored public lazy var idleSession: S = makeIdle?() ?? makeSessionWithID(UUID())

    /// A new session, for a window.
    @discardableResult
    public func makeSession(id: UUID = UUID()) -> S {
        let session = makeSessionWithID(id)
        sessions.append(session)
        states[id] = WindowState()
        return session
    }

    /// The number that the next window gets when it is opened without one. SwiftUI asks for it more than once for a single window: it is the same until a
    /// session is made with it (otherwise every question would make a session that no window shows).
    public func defaultWindowID() -> UUID { unclaimedID }

    /// The session of a window: the one that has this number, made when there is none (a window that comes back at the launch).
    public func session(for id: UUID) -> S {
        if let known = sessions.first(where: { $0.id == id }) { return known }
        if id == unclaimedID { unclaimedID = UUID() }
        return makeSession(id: id)
    }

    /// The sessions that a window has shown: one that is only being opened, or was made for nothing, is not one to list.
    public var shownSessions: [S] { sessions.filter { states[$0.id]?.shownOnce == true } }

    /// Takes a session away (its window is not asked about).
    public func remove(_ session: S) {
        sessions.removeAll { $0 === session }
        states[session.id] = nil
    }

    // MARK: Windows

    /// The window that shows a session, once the view has found it.
    public func window(of session: S) -> NSWindow? { states[session.id]?.window }

    /// Called when the window of a session is there.
    public func attach(_ window: NSWindow, to session: S) {
        var state = states[session.id] ?? WindowState()
        state.window = window
        state.shownOnce = true
        state.attachedAt = Date()
        states[session.id] = state
        presenceChanged()
        // The window is on the screen a moment later: the application is looked at again then (it is not the menu bar's business before).
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            self?.presenceChanged()
        }
    }

    /// How long a window that was just found is given to be on the screen.
    @ObservationIgnored public var settlingTime: TimeInterval = 1

    /// Whether the window of a session is not there to be seen: closed (what runs goes on), minimized or hidden.
    public func isWindowHidden(_ session: S) -> Bool {
        guard let state = states[session.id], state.shownOnce else { return false }
        guard let window = state.window else { return true }
        if window.isMiniaturized { return true }
        // A window that has just been found is not on the screen yet: it is not one that was hidden.
        if !window.isVisible, Date().timeIntervalSince(state.attachedAt) < settlingTime { return false }
        return !window.isVisible
    }

    /// The window of a session is closing: asks the session, and notes that what runs goes on without the window when it was said.
    public func windowShouldClose(_ session: S) -> Bool {
        switch session.decisionForClosingWindow() {
        case .cancel: return false
        case .keepRunning: states[session.id]?.keepsRunning = true; return true
        case .stop: states[session.id]?.keepsRunning = false; return true
        }
    }

    /// The window of a session is closed. The session goes with it and what it runs is stopped, unless the person said that it goes on: the session then
    /// stays, without a window, and the menu bar is where it is reached.
    public func windowClosed(_ session: S) {
        states[session.id]?.window = nil
        if states[session.id]?.keepsRunning == true, session.isActive {
            states[session.id]?.keepsRunning = false
        } else {
            session.stopNow()
            remove(session)
        }
        presenceChanged()
    }

    /// Takes a session away that has no window (what is not saved is asked about first, and what runs is stopped).
    public func discard(_ session: S) {
        guard session.confirmDiscard() else { return }
        session.stopNow()
        remove(session)
        presenceChanged()
    }

    // MARK: Presence: the Dock, the menu bar

    /// The sessions that run.
    public var runningCount: Int { sessions.filter(\.isActive).count }
    public var anyRunning: Bool { runningCount > 0 }

    /// The icon of the menu bar is there while something is to be reached from it: a session that runs, a window that is not seen, or several sessions.
    public var showsMenuBarIcon: Bool {
        _ = presence
        return anyRunning || shownSessions.contains { isWindowHidden($0) } || shownSessions.count >= 2
    }

    private var sessionsWindow: NSWindow? { NSApp.windows.first { $0.title == configuration.sessionsWindowTitle } }

    /// A window came, went or changed: the application shows in the Dock while a window is seen or something runs, and only in the menu bar otherwise.
    public func presenceChanged() {
        presence += 1
        // A session that no window ever showed and that does nothing is dropped (it was made for a window that did not come).
        let stale = sessions.filter { states[$0.id]?.shownOnce != true && !$0.isActive && Date().timeIntervalSince(states[$0.id]?.created ?? .now) > 5 }
        for session in stale { remove(session) }
        // The window that lists the sessions counts as a window that is seen: the application stays in the Dock while it is there.
        let seen = shownSessions.contains { !isWindowHidden($0) } || (sessionsWindow?.isVisible ?? false)
        // The Dock stays while something runs, even with no window: an icon of the menu bar can be hidden (by the notch, by the menus of another
        // application), and a running session, which takes the processor or the disk, must not be left without a sign that cannot be missed.
        let policy: NSApplication.ActivationPolicy = seen || sessions.isEmpty || anyRunning ? .regular : .accessory
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
            // An application that becomes a regular one again is not the active one: without this its menus and its name stay out of the menu bar
            // (JackMate does the same). Only for a window that is there to be seen, never to take the focus from what the person is doing.
            if policy == .regular, seen { NSApp.activate(ignoringOtherApps: true) }
        }
        if configuration.showsDockBadge { NSApp.dockTile.badgeLabel = runningCount > 0 ? String(runningCount) : nil }
    }

    /// Follows what runs: the Dock is kept while a session runs, and let go of when the last one ends with no window to show.
    private func trackRunning() {
        withObservationTracking {
            _ = runningCount
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.presenceChanged()
                self?.trackRunning()
            }
        }
    }

    /// Starts listening to what changes the windows: one that is minimized or comes back, the application that is hidden.
    public func watchWindows() {
        guard presenceObservers.isEmpty else { return }
        trackRunning()
        let center = NotificationCenter.default
        for name in [NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification, NSApplication.didHideNotification, NSApplication.didUnhideNotification] {
            presenceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.presenceChanged() }
            })
        }
    }

    // MARK: Showing

    /// Brings the window of a session back, or opens one for it (a session whose window was closed while it went on).
    public func showWindow(of session: S) {
        NSApp.setActivationPolicy(.regular)
        // The window that lists the sessions has done its job.
        sessionsWindow?.close()
        if let window = states[session.id]?.window {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            presenceChanged()
            return
        }
        openWindowAction?(session.id)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Brings back every window (and opens the ones that were closed while their session went on); the list of sessions has then done its job.
    public func showAllWindows() {
        NSApp.setActivationPolicy(.regular)
        sessionsWindow?.close()
        for session in shownSessions {
            if let window = states[session.id]?.window {
                if window.isMiniaturized { window.deminiaturize(nil) }
                window.orderFront(nil)
            } else {
                openWindowAction?(session.id)
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        presenceChanged()
    }

    /// Closes every window. What runs goes on without its window (the session stays, in the menu bar); a session that does nothing is closed, after what is
    /// not saved has been asked about, and one that says no stays. When no session is left the application ends, as it does when the last window closes.
    public func closeAll() {
        for session in sessions {
            if session.isActive {
                // What runs is not stopped: only its window goes.
                guard let window = states[session.id]?.window else { continue }
                states[session.id]?.keepsRunning = true
                window.close()
                if sessions.contains(where: { $0 === session }), states[session.id]?.window != nil { windowClosed(session) }
            } else {
                guard session.confirmDiscard() else { continue }
                states[session.id]?.keepsRunning = false
                if let window = states[session.id]?.window { window.close() }
                // A window that has a guard has told the hub already; one that has none (or none any more) is closed here.
                if sessions.contains(where: { $0 === session }) { windowClosed(session) }
            }
        }
        sessionsWindow?.close()
        presenceChanged()
    }

    /// Shows the window that lists the sessions: what the click on the icon of the Dock leads to when several sessions have no window.
    public func showSessionsWindow() {
        NSApp.setActivationPolicy(.regular)
        if let window = sessionsWindow, window.isVisible { window.makeKeyAndOrderFront(nil) } else { openSessionsAction?() }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Opens a window on a session that was just made (a tool that made it and filled it). The session is dropped if no window can be opened.
    public func show(_ session: S) {
        guard let openWindowAction else { remove(session); return }
        NSApp.setActivationPolicy(.regular)
        openWindowAction(session.id)
    }

    /// A new session in a window of its own (from the menu bar, where no window may be open).
    @discardableResult
    public func newSession() -> S {
        let fresh = makeSession()
        show(fresh)
        return fresh
    }

    // MARK: The application

    /// What the application answers when its last window closes: it stays while a session goes on without its window.
    public var shouldTerminateAfterLastWindowClosed: Bool { shownSessions.isEmpty }

    /// The click on the icon of the Dock while no window is seen: the window of the one session that has none, the list of them when there are several. What
    /// is already open stays as it is, and with no session at all it is the usual new window. Returns whether the system is to do its usual.
    public func handleReopen(hasVisibleWindows: Bool) -> Bool {
        guard !hasVisibleWindows else { return true }
        let hidden = shownSessions.filter { isWindowHidden($0) }
        switch hidden.count {
        case 0: return true
        case 1: showWindow(of: hidden[0]); return false
        default: showSessionsWindow(); return false
        }
    }

    /// What the application answers when it is asked to quit: every session is asked (one that says no keeps the application open), then what runs is
    /// stopped, and the application waits for the ones that take a moment.
    public func terminateReply() -> NSApplication.TerminateReply {
        for session in sessions where !session.confirmQuit() { return .terminateCancel }
        let running = sessions.filter(\.isActive)
        guard !running.isEmpty else { return .terminateNow }
        let waiting = QuitWaiting()
        waiting.remaining = running.count
        for session in running {
            session.stopForQuit {
                waiting.remaining -= 1
                if waiting.remaining == 0 {
                    if waiting.returnedLater { NSApp.reply(toApplicationShouldTerminate: true) } else { waiting.finishedEarly = true }
                }
            }
        }
        if waiting.finishedEarly { return .terminateNow }
        waiting.returnedLater = true
        return .terminateLater
    }
}
