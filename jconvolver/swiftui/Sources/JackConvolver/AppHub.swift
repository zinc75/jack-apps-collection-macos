// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation
import JConvolverKit
import Observation
import SessionKit
import SoundFileKit
import UniformTypeIdentifiers

/// What the whole application shares, whatever the number of windows: the state of JACK (one client for all of them), what is known of the sound files, the
/// recent files and the settings that are kept between launches. Each window has a session (`AppModel`): its configuration, its engine, its page. The windows,
/// the menu bar and the Dock are the business of `SessionKit`.
@MainActor
@Observable
final class AppHub {
    let jack = JackStatus()
    @ObservationIgnored let catalog = SoundFileCatalog()
    @ObservationIgnored let defaults: UserDefaults

    private(set) var recents: [URL] = []

    /// The sessions, their windows, the icon of the menu bar and the Dock.
    @ObservationIgnored private(set) var sessionHub: SessionHub<AppModel>!

    /// The sessions, in the order they were made.
    var sessions: [AppModel] { sessionHub.sessions }

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
        sessionHub = SessionHub(configuration: SessionKitConfiguration(toolName: "Jack Convolver", showsDockBadge: true,
                                                                       runningNoun: "moteur", runningNounPlural: "moteurs")) { [unowned self] id in
            AppModel(hub: self, id: id)
        }
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
            case .first: sessionHub.showWindow(of: other)
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
        let fresh = sessionHub.makeSession()
        fresh.load(url, asCopy: asCopy)
        sessionHub.show(fresh)
    }

    private func openNewInNewWindow(inputs: Int, outputs: Int) {
        let fresh = sessionHub.makeSession()
        fresh.create(inputs: inputs, outputs: outputs)
        sessionHub.show(fresh)
    }

    /// Opens a configuration chosen in a panel, in a session of its own (the window that lists the sessions has none to open it in).
    func openInNewSession() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "conf") ?? .plainText]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "Choisissez un fichier de configuration de jconvolver.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let fresh = sessionHub.makeSession()
        open(url, from: fresh)
        if fresh.isOpen { sessionHub.show(fresh) } else { sessionHub.remove(fresh) }
    }

    // MARK: JACK

    /// Connects to JACK (once, whatever the number of sessions). The xruns that JACK counts are the ones of every engine.
    func start() {
        jack.onXruns = { [weak self] count in
            guard let self else { return }
            for session in self.sessions { for _ in 0..<count { session.controller.recordXrun() } }
        }
        // A connection made or removed elsewhere: every engine that runs adopts what the graph has.
        jack.onLinksChanged = { [weak self] in
            self?.sessions.forEach { $0.adoptRealConnections() }
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
