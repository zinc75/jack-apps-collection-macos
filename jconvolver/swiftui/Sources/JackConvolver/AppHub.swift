// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation
import JConvolverKit
import Observation
import SoundFileKit
import UniformTypeIdentifiers

/// What the whole application shares, whatever the number of windows: the state of JACK (one client for all of them), what is known of the sound files, the
/// recent files and the settings that are kept between launches. Each window has a session (`AppModel`): its configuration, its engine, its page.
@MainActor
@Observable
final class AppHub {
    let jack = JackStatus()
    @ObservationIgnored let catalog = SoundFileCatalog()
    @ObservationIgnored let defaults: UserDefaults

    private(set) var recents: [URL] = []
    /// The sessions, in the order they were made.
    private(set) var sessions: [AppModel] = []

    /// Whether the card with what is on a cell shows above the matrix, under the pointer. Kept between launches.
    var showsHoverCard = true {
        didSet { defaults.set(showsHoverCard, forKey: "showsHoverCard") }
    }

    /// What a click on an inspect button does when other responses are already drawn.
    var inspectChoice = InspectChoice(rawValue: UserDefaults.standard.string(forKey: "inspectChoice") ?? "") ?? .ask {
        didSet { UserDefaults.standard.set(inspectChoice.rawValue, forKey: "inspectChoice") }
    }

    /// - Parameter defaults: where the settings are kept; nil for a throw-away store (the debug aids use it: they must not touch
    ///   what the person has set up).
    init(defaults: UserDefaults?) {
        self.defaults = defaults ?? UserDefaults(suiteName: "jackconvolver.debug.\(UUID().uuidString)") ?? .standard
        showsHoverCard = self.defaults.object(forKey: "showsHoverCard") as? Bool ?? true
        recents = (self.defaults.stringArray(forKey: "recentFiles") ?? []).map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Opens a window on a session (set by the first window: the scene knows how).
    @ObservationIgnored var openWindowAction: ((UUID) -> Void)?
    /// Opens the window that lists the sessions.
    @ObservationIgnored var openSessionsAction: (() -> Void)?

    /// The title of the window that lists the sessions (it is how it is found among the windows).
    static let sessionsWindowTitle = "Jack Convolver · Sessions"

    private var sessionsWindow: NSWindow? { NSApp.windows.first { $0.title == Self.sessionsWindowTitle } }

    /// Shows the window that lists the sessions: what the click on the icon of the Dock leads to when several engines have no window.
    func showSessionsWindow() {
        NSApp.setActivationPolicy(.regular)
        if let window = sessionsWindow, window.isVisible { window.makeKeyAndOrderFront(nil) } else { openSessionsAction?() }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// A session that no window shows: what the commands of the menus act on while no window has the focus, so that they do nothing.
    @ObservationIgnored lazy var idleSession = AppModel(hub: self)

    /// A new session, for a window.
    func makeSession(id: UUID = UUID()) -> AppModel {
        let session = AppModel(hub: self, id: id)
        sessions.append(session)
        return session
    }

    /// The number that the next window gets when it is opened without one. SwiftUI asks for it more than once for a single window: it is the same until a
    /// session is made with it (otherwise every question would make a session that no window shows).
    @ObservationIgnored private var unclaimedID = UUID()

    func defaultWindowID() -> UUID { unclaimedID }

    /// The session of a window: the one that has this number, made when there is none (a window that comes back at the launch).
    func session(for id: UUID) -> AppModel {
        if let known = sessions.first(where: { $0.id == id }) { return known }
        if id == unclaimedID { unclaimedID = UUID() }
        return makeSession(id: id)
    }

    /// The sessions that a window has shown: a session that is only being opened, or was made for nothing, is not one to list.
    var shownSessions: [AppModel] { sessions.filter(\.shownOnce) }

    /// The window of a session is closed. The session goes with it and its engine is stopped, unless the person said that the engine goes on: the session
    /// then stays, without a window, and the menu bar is where it is reached.
    func close(_ session: AppModel) {
        session.window = nil
        if session.keepsRunning, session.controller.isRunning {
            session.keepsRunning = false
        } else {
            session.controller.stop()
            sessions.removeAll { $0 === session }
        }
        presenceChanged()
    }

    /// Takes a session away without a window (its engine is stopped, after what is not saved has been asked about).
    func discard(_ session: AppModel) {
        guard session.confirmLeaving(.open) else { return }
        session.controller.stop()
        sessions.removeAll { $0 === session }
        presenceChanged()
    }

    // MARK: Windows and the menu bar

    /// Counts the changes of what is seen of the windows (they are not observable): the menu bar reads it.
    private(set) var presence = 0

    @ObservationIgnored private var presenceObservers: [NSObjectProtocol] = []

    /// Follows the engines: the Dock is kept while one runs, and let go of when the last one ends with no window to show.
    private func trackRunning() {
        withObservationTracking {
            _ = anyRunning
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.presenceChanged()
                self?.trackRunning()
            }
        }
    }

    /// Starts listening to what changes the windows: one that is minimized or comes back, the application that is hidden.
    func watchWindows() {
        guard presenceObservers.isEmpty else { return }
        trackRunning()
        let center = NotificationCenter.default
        for name in [NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification, NSApplication.didHideNotification, NSApplication.didUnhideNotification] {
            presenceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.presenceChanged() }
            })
        }
    }

    /// A window came, went or changed: the application shows in the Dock while a window is seen, and only in the menu bar otherwise.
    func presenceChanged() {
        presence += 1
        // A session that no window ever showed and that does nothing is dropped (it was made for a window that did not come).
        sessions.removeAll { !$0.shownOnce && !$0.controller.isRunning && Date().timeIntervalSince($0.created) > 5 }
        // The window that lists the sessions counts as a window that is seen: the application stays in the Dock while it is there.
        let seen = sessions.contains { $0.shownOnce && !$0.isWindowHidden } || (sessionsWindow?.isVisible ?? false)
        // The Dock stays while an engine runs, even with no window: an icon of the menu bar can be hidden (by the notch, by the menus of another
        // application), and a running engine, which takes the processor or the disk, must not be left without a sign that cannot be missed.
        NSApp.setActivationPolicy(seen || sessions.isEmpty || anyRunning ? .regular : .accessory)
    }

    /// Whether an engine runs.
    var anyRunning: Bool { sessions.contains { $0.controller.isRunning } }

    /// The icon of the menu bar is there while something is to be reached from it: an engine that runs, a window that is not seen, or several sessions.
    var showsMenuBarIcon: Bool {
        _ = presence
        return anyRunning || shownSessions.contains { $0.isWindowHidden } || shownSessions.count >= 2
    }

    /// Brings the window of a session back, or opens one for it (a session whose window was closed while its engine went on).
    func showWindow(of session: AppModel) {
        NSApp.setActivationPolicy(.regular)
        // The window that lists the sessions has done its job.
        sessionsWindow?.close()
        if let window = session.window {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            presenceChanged()
            return
        }
        openWindowAction?(session.id)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: Opening

    private enum Choice { case first, second, cancel }

    /// A question with two ways to go on and a way out; the first is the default.
    private func ask(_ message: String, _ info: String, first: String, second: String) -> Choice {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = info
        alert.addButton(withTitle: first)
        alert.addButton(withTitle: second)
        alert.addButton(withTitle: String(localized: "Annuler")).keyEquivalent = "\u{1b}"
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .first
        case .alertSecondButtonReturn: return .second
        default: return .cancel
        }
    }

    /// Opens a configuration for the window of `session`. On the home page it opens there. Where a configuration is open already the person is asked whether
    /// to open a new session or to replace it (a new session without asking when its engine runs, since it cannot be replaced). A file that another window
    /// has open is not opened twice without saying: show that window, or open a copy.
    func open(_ url: URL, from session: AppModel) {
        let name = url.lastPathComponent
        // A file that is open in a window, this one included, is not opened a second time as it is: two windows on one file would write over each other.
        if let other = sessions.first(where: { $0.fileURL?.standardizedFileURL == url.standardizedFileURL }) {
            let here = other === session
            switch ask(here ? String(localized: "« \(name) » est déjà ouvert dans cette fenêtre.") : String(localized: "« \(name) » est déjà ouvert dans une autre fenêtre."),
                       String(localized: "Une copie est une session de plus sur ce fichier : elle s'enregistre sous un autre nom."),
                       first: here ? String(localized: "Rester dans cette fenêtre") : String(localized: "Afficher la fenêtre existante"),
                       second: String(localized: "Nouvelle session (copie)")) {
            case .first: other.showWindow()
            case .second: openInNewWindow(url, asCopy: true)
            case .cancel: break
            }
            return
        }
        guard session.isOpen else { session.load(url); return }
        if session.isLocked { openInNewWindow(url); return }
        switch ask(String(localized: "Une configuration est déjà ouverte dans cette fenêtre."),
                   String(localized: "Ouvrir « \(name) » dans une nouvelle session, ou remplacer la configuration en cours ?"),
                   first: String(localized: "Nouvelle session"), second: String(localized: "Remplacer la configuration en cours")) {
        case .first: openInNewWindow(url)
        case .second: session.load(url)
        case .cancel: break
        }
    }

    /// A new configuration for the window of `session`, with the same question.
    func newConfiguration(inputs: Int, outputs: Int, from session: AppModel) {
        guard session.isOpen else { session.create(inputs: inputs, outputs: outputs); return }
        if session.isLocked { openNewInNewWindow(inputs: inputs, outputs: outputs); return }
        switch ask(String(localized: "Une configuration est déjà ouverte dans cette fenêtre."),
                   String(localized: "Créer la nouvelle configuration dans une nouvelle session, ou remplacer la configuration en cours ?"),
                   first: String(localized: "Nouvelle session"), second: String(localized: "Remplacer la configuration en cours")) {
        case .first: openNewInNewWindow(inputs: inputs, outputs: outputs)
        case .second: session.create(inputs: inputs, outputs: outputs)
        case .cancel: break
        }
    }

    private func openInNewWindow(_ url: URL, asCopy: Bool = false) {
        let fresh = makeSession()
        fresh.load(url, asCopy: asCopy)
        show(fresh)
    }

    private func openNewInNewWindow(inputs: Int, outputs: Int) {
        let fresh = makeSession()
        fresh.create(inputs: inputs, outputs: outputs)
        show(fresh)
    }

    /// Brings back every window (and opens the ones that were closed while their engine went on), then the list of sessions has done its job.
    func showAllWindows() {
        NSApp.setActivationPolicy(.regular)
        sessionsWindow?.close()
        for session in shownSessions {
            if let window = session.window {
                if window.isMiniaturized { window.deminiaturize(nil) }
                window.orderFront(nil)
            } else {
                openWindowAction?(session.id)
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        presenceChanged()
    }

    /// Opens a configuration chosen in a panel, in a session of its own (the window that lists the sessions has none to open it in).
    func openInNewSession() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "conf") ?? .plainText]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "Choisissez un fichier de configuration de jconvolver.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let fresh = makeSession()
        open(url, from: fresh)
        if fresh.isOpen { show(fresh) } else { remove(fresh) }
    }

    /// A new session in a window of its own, on the home page (from the menu bar, where no window may be open).
    func newSession() {
        let fresh = makeSession()
        show(fresh)
    }

    private func show(_ session: AppModel) {
        guard let openWindowAction else { remove(session); return }
        NSApp.setActivationPolicy(.regular)
        openWindowAction(session.id)
    }

    private func remove(_ session: AppModel) { sessions.removeAll { $0 === session } }

    /// Connects to JACK (once, whatever the number of sessions). The xruns that JACK counts are the ones of every engine.
    func start() {
        jack.onXruns = { [weak self] count in
            guard let self else { return }
            for session in self.sessions { for _ in 0..<count { session.controller.recordXrun() } }
        }
        jack.start()
    }

    /// Stops every engine, and the connection to JACK.
    func shutdown() {
        for session in sessions { session.controller.stop() }
        jack.stop()
    }

    // MARK: Recent files

    /// Takes a file off the list of recent ones (the file itself is left alone).
    func forgetRecent(_ url: URL) {
        recents.removeAll { $0 == url }
        defaults.set(recents.map(\.path), forKey: "recentFiles")
    }

    func clearRecents() {
        recents = []
        defaults.set([String](), forKey: "recentFiles")
    }

    func remember(_ url: URL) {
        recents.removeAll { $0 == url }
        recents.insert(url, at: 0)
        recents = Array(recents.prefix(8))
        defaults.set(recents.map(\.path), forKey: "recentFiles")
    }
}
