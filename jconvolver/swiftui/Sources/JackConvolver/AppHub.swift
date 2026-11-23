// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import JConvolverKit
import Observation
import SoundFileKit

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

    /// A new session, for a window.
    func makeSession() -> AppModel {
        let session = AppModel(hub: self)
        sessions.append(session)
        return session
    }

    func remove(_ session: AppModel) {
        sessions.removeAll { $0 === session }
    }

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
