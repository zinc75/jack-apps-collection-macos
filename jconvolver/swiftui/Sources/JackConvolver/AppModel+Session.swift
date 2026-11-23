// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SessionKit

/// What the sessions kit asks of a session: what to show of it in the lists, whether it runs, and how to start it, stop it and leave it.
extension AppModel: HostedSession {
    var isActive: Bool { controller.isRunning }

    /// The engine can be started and stopped from the lists in real time; the processing of a sound file is started from its window.
    var canStartFromList: Bool { mode == .realTime }

    var canToggle: Bool { isOpen && (controller.isRunning || !hasErrors) }

    func toggle() { toggleRun() }

    func confirmQuit() -> Bool { confirmLeaving(.quit) }

    func stopNow() { controller.stop() }

    func confirmDiscard() -> Bool { confirmLeaving(.open) }

    /// What a card of the list of sessions shows.
    var card: SessionCard {
        let c = controller
        let running = c.isRunning, failed = c.endedOnAProblem
        var badges: [SessionBadge] = [], gauges: [SessionGauge] = [], notes: [SessionNote] = []
        let stateText: String
        if running {
            stateText = mode == .file ? String(localized: "traitement en cours") : String(localized: "moteur en cours d'exécution")
            // The name JACK gave its client, to find it in the patchbay (not known for the first instants of a run).
            if mode == .realTime, let name = runClientName { badges.append(SessionBadge(name, symbol: "cable.connector")) }
            let share = c.machineShare ?? 0
            gauges.append(SessionGauge(String(localized: "Moteur"), value: min(1, share), text: share < 0.01 ? "< 1 %" : "\(Int((share * 100).rounded())) %"))
            notes.append(SessionNote("xruns \(c.xruns)", isAlert: c.xruns > 0))
        } else if failed {
            stateText = String(localized: "Moteur arrêté sur une erreur")
        } else if !isOpen {
            stateText = String(localized: "Aucune configuration ouverte")
        } else {
            stateText = hub.sessionHub.isWindowHidden(self) ? String(localized: "En configuration, fenêtre non affichée") : String(localized: "En configuration")
        }
        return SessionCard(title: displayName + (isCopy ? " (" + String(localized: "copie") + ")" : ""), isModified: isEdited, subtitle: details,
                           state: running ? .active : failed ? .failed : .idle, stateText: stateText, badges: badges, gauges: gauges, notes: notes)
    }

    /// What the configuration holds, in a line.
    private var details: String {
        guard let d = document else { return String(localized: "Aucune configuration ouverte") }
        let inputs = d.inputCount == 1 ? String(localized: "1 entrée") : String(localized: "\(d.inputCount) entrées")
        let outputs = d.outputCount == 1 ? String(localized: "1 sortie") : String(localized: "\(d.outputCount) sorties")
        let n = d.placedPairs
        let responses = n == 0 ? String(localized: "aucune réponse impulsionnelle") : n == 1 ? String(localized: "1 réponse impulsionnelle") : String(localized: "\(n) réponses impulsionnelles")
        return "\(inputs) · \(outputs) · \(responses)"
    }
}
