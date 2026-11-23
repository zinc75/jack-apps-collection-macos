// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import JackPlayKit
import SessionKit

/// What the sessions kit asks of a session: what to show of it in the lists, whether it plays, and how to start it, stop it and leave it.
extension AppModel: HostedSession {
    /// A file plays (a file that waits, paused, is not something that runs).
    var isActive: Bool { player.isPlaying }

    var canStartFromList: Bool { true }

    /// The button of the list: plays, or pauses.
    var canToggle: Bool { player.canCommand }

    func toggle() { player.togglePlay() }

    func confirmDiscard() -> Bool { true }

    /// Quitting is not asked about: nothing is lost when the sound stops.
    func confirmQuit() -> Bool { true }

    /// What stops with the session: the program of the file and the one of the next file.
    func stopNow() { shutdown() }

    /// What closing the window leads to. A file that plays can go on without the window: the session stays in the menu bar.
    func decisionForClosingWindow() -> WindowCloseDecision {
        guard player.isPlaying else { return .stop }
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = String(localized: "Un fichier est en cours de lecture.")
        alert.informativeText = String(localized: "Vous pouvez fermer la fenêtre et laisser la lecture continuer : la session reste dans la barre des menus, d'où vous pourrez rouvrir la fenêtre ou arrêter la lecture.")
        alert.addButton(withTitle: String(localized: "Fermer la fenêtre"))
        alert.addButton(withTitle: String(localized: "Arrêter et fermer"))
        alert.addButton(withTitle: String(localized: "Annuler")).keyEquivalent = "\u{1b}"
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .keepRunning
        case .alertSecondButtonReturn: return .stop
        default: return .cancel
        }
    }

    /// What names the session: the file that is open, else the first of the list, else nothing.
    var label: String {
        if let file = player.file { return file.url.lastPathComponent }
        if let first = playlist.playlist.items.first { return first.lastPathComponent }
        return String(localized: "aucun fichier")
    }

    /// The title of the window: the application, then the file.
    var windowTitle: String {
        player.file.map { "Jack Play · " + $0.url.lastPathComponent } ?? "Jack Play"
    }

    /// What a card of the list of sessions shows.
    var card: SessionCard {
        var stateText: String
        var state = SessionState.idle
        switch player.phase {
        case .empty: stateText = String(localized: "aucun fichier")
        case .starting: stateText = String(localized: "démarrage")
        case .running(let s):
            switch s {
            case .playing: stateText = String(localized: "lecture en cours"); state = .active
            case .paused: stateText = String(localized: "en pause")
            case .ended: stateText = String(localized: "fin du fichier")
            }
        case .failed(let failure):
            state = .failed
            stateText = failure == .noJack ? String(localized: "JACK non démarré") : String(localized: "lecture impossible")
        }
        var parts: [String] = []
        let count = playlist.playlist.count
        if count > 1, let current = playlist.playlist.current { parts.append("\(current + 1) / \(count)") }
        if let info = player.file?.info {
            parts.append(info.channels == 1 ? String(localized: "1 voie") : String(localized: "\(info.channels) voies"))
            parts.append((info.sampleRate / 1000).formatted(.number.precision(.fractionLength(0...1))) + " kHz")
        }
        var badges: [SessionBadge] = [], gauges: [SessionGauge] = []
        if player.isRunning, player.duration > 0 {
            badges.append(SessionBadge(Self.clock(player.positionSeconds) + " / " + Self.clock(player.duration), symbol: "play.circle"))
            gauges.append(SessionGauge(String(localized: "Position"), value: player.fraction,
                                       text: String(localized: "reste \(Self.clock(max(player.duration - player.positionSeconds, 0)))")))
        }
        return SessionCard(title: label, subtitle: parts.joined(separator: " · "), state: state, stateText: stateText, badges: badges, gauges: gauges)
    }

    /// "3:05" or "1:02:03" for a duration in seconds.
    static func clock(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded(.down)))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}
