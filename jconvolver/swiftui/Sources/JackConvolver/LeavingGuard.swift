// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SessionKit
import SwiftUI

/// Why the configuration that is open is about to be left.
enum LeaveReason { case close, quit, open, new }

extension AppModel {
    /// What closing the window leads to. The engine in real time can go on without the window: it stays in the menu bar, where it is stopped or the window comes
    /// back; what is not saved stays in the session, so nothing is asked about it then. (The processing of a sound file ends by itself: closing stops it.)
    func decisionForClosingWindow() -> WindowCloseDecision {
        var stopAsked = false
        if controller.isRunning, mode == .realTime {
            let ask = NSAlert()
            ask.alertStyle = .informational
            ask.messageText = String(localized: "Le moteur jconvolver est en cours d'exécution.")
            ask.informativeText = String(localized: "Vous pouvez fermer la fenêtre et laisser le moteur s'exécuter : il reste dans la barre des menus, d'où vous pourrez rouvrir la fenêtre ou l'arrêter.")
            ask.addButton(withTitle: String(localized: "Fermer la fenêtre"))
            ask.addButton(withTitle: String(localized: "Arrêter et fermer"))
            ask.addButton(withTitle: String(localized: "Annuler")).keyEquivalent = "\u{1b}"
            switch ask.runModal() {
            case .alertFirstButtonReturn: return .keepRunning
            case .alertSecondButtonReturn: stopAsked = true
            default: return .cancel
            }
        }
        return confirmLeaving(.close, stopAsked: stopAsked) ? .stop : .cancel
    }

    /// Asks, when something would be lost, whether to go on: a configuration with changes that are not saved (save, do not save, cancel), and the
    /// engine that runs and that closing the window or quitting stops. Returns whether to go on.
    @MainActor
    func confirmLeaving(_ reason: LeaveReason, stopAsked: Bool = false) -> Bool {
        let stops = controller.isRunning && (reason == .close || reason == .quit)
        guard isEdited || (stops && !stopAsked) else { return true }
        let alert = NSAlert()
        alert.alertStyle = .warning
        if isEdited {
            alert.messageText = String(localized: "Enregistrer les modifications de « \(name) » ?")
            alert.informativeText = stops
                ? String(localized: "Si vous ne les enregistrez pas, elles seront perdues. Le moteur en cours d'exécution sera arrêté.")
                : String(localized: "Si vous ne les enregistrez pas, elles seront perdues.")
            let saveButton = alert.addButton(withTitle: savesAsNew ? String(localized: "Enregistrer sous…") : String(localized: "Enregistrer"))
            saveButton.keyEquivalent = "\r"
            let cancel = alert.addButton(withTitle: String(localized: "Annuler"))
            cancel.keyEquivalent = "\u{1b}"
            let discard = alert.addButton(withTitle: String(localized: "Ne pas enregistrer"))
            discard.keyEquivalent = "d"
            discard.keyEquivalentModifierMask = .command
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                guard save() else { return false }
            case .alertSecondButtonReturn:
                return false
            default:
                break
            }
        } else {
            let program = mode == .file ? "fconvolver" : "jconvolver"
            // Quitting can concern an engine whose window is closed: it is named.
            alert.messageText = reason == .quit && hub.sessionHub.isWindowHidden(self)
                ? String(localized: "Le moteur \(program) de « \(displayName) » est en cours d'exécution.")
                : String(localized: "Le moteur \(program) est en cours d'exécution.")
            alert.informativeText = reason == .quit
                ? String(localized: "Quitter l'application l'arrête.")
                : String(localized: "Fermer la fenêtre l'arrête.")
            alert.addButton(withTitle: reason == .quit ? String(localized: "Arrêter et quitter") : String(localized: "Arrêter et fermer"))
            alert.addButton(withTitle: String(localized: "Annuler")).keyEquivalent = "\u{1b}"
            guard alert.runModal() == .alertFirstButtonReturn else { return false }
        }
        return true
    }
}
