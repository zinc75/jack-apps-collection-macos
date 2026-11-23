// SPDX-License-Identifier: GPL-2.0-or-later

import AppKit
import JackCaptureKit
import SessionKit

/// What the sessions kit asks of a session: what to show of it in the lists, whether it records, and how to start it, stop it and leave it.
extension RecorderModel: HostedSession {
    /// Something is written, or waits to be (an armed recording keeps the Dock too).
    public var isActive: Bool { isBusy }

    public var canStartFromList: Bool { true }

    /// The red button of the list: it records, or stops what records. A recording that is closing its file cannot be touched.
    public var canToggle: Bool { isBusy ? phase != .stopping : graph.isConnected }

    public func toggle() { toggleRecording() }

    public func confirmDiscard() -> Bool { true }

    public func stopForQuit(completion: @escaping @MainActor () -> Void) {
        stopForQuit { MainActor.assumeIsolated { completion() } }
    }

    /// What closing the window leads to. A recording can go on without the window: it stays in the menu bar, where it is stopped or the window comes back.
    public func decisionForClosingWindow() -> WindowCloseDecision {
        guard isBusy else { return .stop }
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = phase == .armed ? String(localized: "Un enregistrement est armé.") : String(localized: "Un enregistrement est en cours.")
        alert.informativeText = String(localized: "Vous pouvez fermer la fenêtre et laisser l'enregistrement continuer : il reste dans la barre des menus, d'où vous pourrez rouvrir la fenêtre ou l'arrêter. Si vous l'arrêtez, le fichier est refermé proprement.")
        alert.addButton(withTitle: String(localized: "Fermer la fenêtre"))
        alert.addButton(withTitle: String(localized: "Arrêter et fermer"))
        alert.addButton(withTitle: String(localized: "Annuler")).keyEquivalent = "\u{1b}"
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .keepRunning
        case .alertSecondButtonReturn: return .stop
        default: return .cancel
        }
    }

    /// Quitting stops what is written: asked first, and said which file is written when the window is not there to show it.
    public func confirmQuit() -> Bool {
        guard isWriting else { return true }
        let alert = NSAlert()
        alert.messageText = String(localized: "Un enregistrement est en cours")
        alert.informativeText = String(localized: "Arrêter l'enregistrement et quitter ? Le fichier est refermé proprement.")
        alert.addButton(withTitle: String(localized: "Arrêter et quitter"))
        alert.addButton(withTitle: String(localized: "Annuler"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// What a card of the list of sessions shows.
    public var card: SessionCard {
        let busy = isBusy
        let failed = !busy && errorMessage != nil
        var badges: [SessionBadge] = [], gauges: [SessionGauge] = []
        let stateText: String
        switch phase {
        case .configuration: stateText = failed ? String(localized: "Impossible de démarrer") : String(localized: "En configuration")
        case .armed: stateText = String(localized: "enregistrement armé")
        case .recording: stateText = String(localized: "enregistrement en cours")
        case .stopping: stateText = String(localized: "fermeture du fichier")
        case .done: stateText = String(localized: "Enregistrement terminé")
        }
        if phase == .recording || phase == .stopping {
            // The time of the recording and, when it stops by itself, what is left of it.
            var text = Self.clock(elapsed)
            if settings.scheduledStop, let launched = settings.durationSeconds as Int?, Double(launched) > elapsed {
                text += " · " + String(localized: "reste \(Self.clock(Double(launched) - elapsed))")
                gauges.append(SessionGauge(String(localized: "Durée"), value: elapsed / Double(max(launched, 1)), text: Self.clock(Double(launched) - elapsed)))
            }
            badges.append(SessionBadge(text, symbol: "record.circle"))
            // The room the disk has left for it, when it is not for days.
            if let left = diskSecondsLeft, left < 48 * 3600 { badges.append(SessionBadge(String(localized: "disque : reste \(Self.remaining(left))"), symbol: "internaldrive")) }
        } else if phase == .armed, let reason = armedReason {
            badges.append(SessionBadge(reason == .timemachine ? String(localized: "timemachine") : String(localized: "attend le départ"), symbol: "hourglass"))
        }
        let name = outputFile ?? settings.baseName
        return SessionCard(title: name, subtitle: subtitle, state: busy ? .active : failed ? .failed : .idle, stateText: stateText, badges: badges, gauges: gauges)
    }

    /// The channels, the format and the rate, in a line.
    private var subtitle: String {
        let channels = settings.channels == 1 ? String(localized: "1 voie") : String(localized: "\(settings.channels) voies")
        return "\(channels) · \(settings.format.fileExtension.uppercased()) · \((Double(sampleRate) / 1000).formatted(.number.precision(.fractionLength(0...1)))) kHz"
    }

    /// "3 h 20", "45 min" for a duration in seconds.
    static func remaining(_ seconds: Double) -> String {
        let minutes = max(0, Int((seconds / 60).rounded(.down)))
        return minutes >= 60 ? "\(minutes / 60) h \(String(format: "%02d", minutes % 60))" : "\(max(minutes, 1)) min"
    }

    /// "01:23:45" for a duration in seconds.
    static func clock(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded(.down)))
        return String(format: "%02d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60)
    }
}
