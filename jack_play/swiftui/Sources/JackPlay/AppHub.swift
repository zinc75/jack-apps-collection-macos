// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import JackPlayKit
import Observation
import SessionKit

/// The application: the hub that every session shares, the sessions with their windows, and what comes from outside.
@MainActor
@Observable
final class AppHub {
    let play: PlayHub
    let sessionHub: SessionHub<AppModel>
    @ObservationIgnored private let launchedAt = Date()

    init(defaults: UserDefaults?) {
        let play = PlayHub(defaults: defaults)
        self.play = play
        sessionHub = SessionHub<AppModel>(
            configuration: SessionKitConfiguration(toolName: "Jack Play", showsDockBadge: true, runningNoun: String(localized: "lecture"), runningNounPlural: String(localized: "lectures")),
            makeSession: { id in AppModel(hub: play, id: id, usesSavedState: play.claimSavedState()) },
            makeIdleSession: { AppModel(hub: play, usesSavedState: false, takesNumber: false) })
        // A session that leaves gives its number back, by whichever way it leaves (a window that never came leaves too).
        sessionHub.onRemove = { $0.shutdown() }
    }

    /// The programs do not outlive the application.
    func shutdown() { for session in sessionHub.sessions { session.shutdown() } }

    // MARK: ⌘N

    /// A session that plays: a new one, at once. A session that is stopped and has something in it (a list, settings that are not the defaults): the person is
    /// asked whether to open a new session or to start this one over. A session with nothing in it is used as it is.
    func requestNewSession(from session: AppModel?) {
        guard let session, sessionHub.window(of: session) != nil else { sessionHub.newSession(); return }
        if session.player.isPlaying { sessionHub.newSession(); return }
        guard session.hasPreparedContent else { sessionHub.showWindow(of: session); return }
        let alert = NSAlert()
        alert.messageText = String(localized: "Cette session a déjà du contenu.")
        alert.informativeText = String(localized: "Ouvrir une nouvelle session, ou repartir de zéro dans celle-ci ?")
        alert.addButton(withTitle: String(localized: "Nouvelle session"))
        alert.addButton(withTitle: String(localized: "Remplacer cette session"))
        alert.addButton(withTitle: String(localized: "Annuler")).keyEquivalent = "\u{1b}"
        switch alert.runModal() {
        case .alertFirstButtonReturn: sessionHub.newSession()
        case .alertSecondButtonReturn: session.resetToDefaults()
        default: break
        }
    }

    // MARK: Files from outside

    /// The session of the window in front, if there is one.
    var frontSession: AppModel? {
        let shown = sessionHub.shownSessions.filter { sessionHub.window(of: $0)?.isVisible == true }
        return shown.first { sessionHub.window(of: $0)?.isKeyWindow == true }
            ?? shown.first { sessionHub.window(of: $0)?.isMainWindow == true }
            ?? (shown.count == 1 ? shown.first : nil)
    }

    /// Files opened from the Finder or dropped on the icon of the Dock, or chosen when no window is in front.
    func openFromOutside(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let target = frontSession
        let plan = OutsideOpenPlan.plan(hasTarget: target != nil, isBlank: target.map { !$0.hasPreparedContent } ?? true,
                                        isPlaying: target?.player.isPlaying ?? false, atLaunch: Date().timeIntervalSince(launchedAt) < 4)
        switch (plan, target) {
        case (.useSession, let session?):
            session.open(urls)
            sessionHub.showWindow(of: session)
        case (.ask, let session?):
            askWhere(urls, target: session)
        default:
            sessionHub.newSession().open(urls)
        }
    }

    private func askWhere(_ urls: [URL], target: AppModel) {
        let alert = NSAlert()
        alert.messageText = urls.count == 1 ? String(localized: "Où ouvrir ce fichier ?") : String(localized: "Où ouvrir ces fichiers ?")
        alert.informativeText = String(localized: "La session \(target.sessionNumber) (\(target.label)) a déjà une liste.")
        alert.addButton(withTitle: String(localized: "Ajouter à la liste de la session \(target.sessionNumber)"))
        alert.addButton(withTitle: String(localized: "Nouvelle session"))
        alert.addButton(withTitle: String(localized: "Annuler")).keyEquivalent = "\u{1b}"
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            target.add(urls)
            sessionHub.showWindow(of: target)
        case .alertSecondButtonReturn:
            sessionHub.newSession().open(urls)
        default: break
        }
    }

    /// "Open…" with no window in front: the files go where a file from the Finder would.
    func chooseFiles() {
        let urls = sessionHub.idleSession.choosePanel(message: String(localized: "Choisir des fichiers audio"))
        openFromOutside(urls)
    }
}
