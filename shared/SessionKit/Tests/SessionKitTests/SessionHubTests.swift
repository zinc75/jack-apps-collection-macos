// SPDX-License-Identifier: MIT

import AppKit
import Observation
import XCTest
@testable import SessionKit

@MainActor
@Observable
final class FakeSession: HostedSession {
    let id: UUID
    var isActive = false
    var canToggle = true
    var closing: WindowCloseDecision = .stop
    var quitAllowed = true
    var discardAllowed = true
    var stops = 0
    /// A session that takes a moment to stop before quitting.
    var completesLater = false
    @ObservationIgnored var pendingCompletion: (@MainActor () -> Void)?

    init(id: UUID) { self.id = id }

    var card: SessionCard { SessionCard(title: "fake", subtitle: "", state: isActive ? .active : .idle, stateText: "") }
    func toggle() { isActive.toggle() }
    func decisionForClosingWindow() -> WindowCloseDecision { closing }
    func confirmQuit() -> Bool { quitAllowed }
    func stopNow() { stops += 1; isActive = false }
    func confirmDiscard() -> Bool { discardAllowed }
    func stopForQuit(completion: @escaping @MainActor () -> Void) {
        if completesLater { pendingCompletion = completion } else { stopNow(); completion() }
    }
}

@MainActor
final class SessionHubTests: XCTestCase {
    private func makeHub() -> SessionHub<FakeSession> {
        _ = NSApplication.shared
        return SessionHub(configuration: SessionKitConfiguration(toolName: "Tool", showsDockBadge: false)) { FakeSession(id: $0) }
    }

    private func window() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled], backing: .buffered, defer: true)
        // A window made by hand is released when it is closed, and the test still holds it.
        window.isReleasedWhenClosed = false
        return window
    }

    func testTheNumberOfANewWindowIsTheSameUntilASessionTakesIt() {
        let hub = makeHub()
        let first = hub.defaultWindowID()
        XCTAssertEqual(hub.defaultWindowID(), first)
        let session = hub.session(for: first)
        XCTAssertEqual(session.id, first)
        XCTAssertNotEqual(hub.defaultWindowID(), first)
    }

    func testTheSessionOfANumberIsMadeOnceAndFoundAgain() {
        let hub = makeHub()
        let id = UUID()
        XCTAssertTrue(hub.session(for: id) === hub.session(for: id))
        XCTAssertEqual(hub.sessions.count, 1)
    }

    func testASessionIsListedOnceAWindowHasShownIt() {
        let hub = makeHub()
        let session = hub.makeSession()
        XCTAssertTrue(hub.shownSessions.isEmpty)
        hub.attach(window(), to: session)
        XCTAssertEqual(hub.shownSessions.count, 1)
    }

    func testClosingTheWindowOfASessionThatDoesNothingRemovesIt() {
        let hub = makeHub()
        let session = hub.makeSession()
        hub.attach(window(), to: session)
        XCTAssertTrue(hub.windowShouldClose(session))
        hub.windowClosed(session)
        XCTAssertTrue(hub.sessions.isEmpty)
        XCTAssertEqual(session.stops, 1)
    }

    func testClosingTheWindowCanBeRefused() {
        let hub = makeHub()
        let session = hub.makeSession()
        session.closing = .cancel
        XCTAssertFalse(hub.windowShouldClose(session))
    }

    func testWhatRunsGoesOnWhenTheWindowIsClosedAndTheSessionStays() {
        let hub = makeHub()
        let session = hub.makeSession()
        hub.attach(window(), to: session)
        session.isActive = true
        session.closing = .keepRunning
        XCTAssertTrue(hub.windowShouldClose(session))
        hub.windowClosed(session)
        XCTAssertEqual(hub.sessions.count, 1)
        XCTAssertEqual(session.stops, 0)
        XCTAssertTrue(session.isActive)
        XCTAssertTrue(hub.isWindowHidden(session))
        XCTAssertTrue(hub.showsMenuBarIcon)
        // The application stays: a session goes on without its window.
        XCTAssertFalse(hub.shouldTerminateAfterLastWindowClosed)
    }

    func testStoppingWhenTheWindowClosesStopsAndRemoves() {
        let hub = makeHub()
        let session = hub.makeSession()
        hub.attach(window(), to: session)
        session.isActive = true
        session.closing = .stop
        XCTAssertTrue(hub.windowShouldClose(session))
        hub.windowClosed(session)
        XCTAssertTrue(hub.sessions.isEmpty)
        XCTAssertEqual(session.stops, 1)
    }

    func testTheMenuBarIconIsThereWhenARunningSessionOrSeveralSessionsOrAHiddenWindow() {
        let hub = makeHub()
        let a = hub.makeSession()
        hub.attach(window(), to: a)
        a.isActive = true
        XCTAssertTrue(hub.showsMenuBarIcon)
        a.isActive = false
        let b = hub.makeSession()
        hub.attach(window(), to: b)
        XCTAssertTrue(hub.showsMenuBarIcon)
    }

    func testASessionWithoutWindowIsDiscardedAfterAsking() {
        let hub = makeHub()
        let session = hub.makeSession()
        hub.attach(window(), to: session)
        session.discardAllowed = false
        hub.discard(session)
        XCTAssertEqual(hub.sessions.count, 1)
        session.discardAllowed = true
        hub.discard(session)
        XCTAssertTrue(hub.sessions.isEmpty)
    }

    func testQuittingAsksEverySessionAndOneCanRefuse() {
        let hub = makeHub()
        let a = hub.makeSession(), b = hub.makeSession()
        b.quitAllowed = false
        XCTAssertEqual(hub.terminateReply(), .terminateCancel)
        b.quitAllowed = true
        a.isActive = false
        XCTAssertEqual(hub.terminateReply(), .terminateNow)
    }

    func testQuittingWaitsForTheSessionsThatTakeAMomentToStop() {
        let hub = makeHub()
        let a = hub.makeSession(), b = hub.makeSession()
        a.isActive = true; b.isActive = true
        a.completesLater = true
        XCTAssertEqual(hub.terminateReply(), .terminateLater)
        XCTAssertEqual(b.stops, 1)
        XCTAssertNotNil(a.pendingCompletion)
    }

    func testClosingEverythingClosesTheWindowsAndLeavesWhatRuns() {
        let hub = makeHub()
        let running = hub.makeSession(), idle = hub.makeSession(), refusing = hub.makeSession(), windowless = hub.makeSession()
        hub.attach(window(), to: running); hub.attach(window(), to: idle); hub.attach(window(), to: refusing)
        running.isActive = true
        refusing.discardAllowed = false
        hub.closeAll()
        // The one that runs stays without a window, the one that refuses stays, the others are gone.
        XCTAssertEqual(hub.sessions.count, 2)
        XCTAssertTrue(hub.sessions.contains { $0 === running })
        XCTAssertTrue(hub.sessions.contains { $0 === refusing })
        XCTAssertEqual(running.stops, 0)
        XCTAssertTrue(running.isActive)
        XCTAssertTrue(hub.isWindowHidden(running))
        XCTAssertEqual(idle.stops, 1)
        XCTAssertFalse(hub.sessions.contains { $0 === windowless })
        // The application stays: a session goes on without its window.
        XCTAssertFalse(hub.shouldTerminateAfterLastWindowClosed)
    }

    func testClickOnTheDockWithAWindowSeenDoesTheUsual() {
        let hub = makeHub()
        XCTAssertTrue(hub.handleReopen(hasVisibleWindows: true))
        // No session at all: a new window as usual.
        XCTAssertTrue(hub.handleReopen(hasVisibleWindows: false))
    }
}
