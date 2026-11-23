// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

/// Why the configuration that is open is about to be left.
enum LeaveReason { case close, quit, open, new }

extension AppModel {
    /// Asks, when something would be lost, whether to go on: a configuration with changes that are not saved (save, do not save, cancel), and the
    /// engine that runs and that closing the window or quitting stops. Returns whether to go on.
    @MainActor
    func confirmLeaving(_ reason: LeaveReason) -> Bool {
        let stops = controller.isRunning && (reason == .close || reason == .quit)
        guard isEdited || stops else { if reason == .close { leavingConfirmed = true }; return true }
        let alert = NSAlert()
        alert.alertStyle = .warning
        if isEdited {
            alert.messageText = String(localized: "Enregistrer les modifications de « \(name) » ?")
            alert.informativeText = stops
                ? String(localized: "Si vous ne les enregistrez pas, elles seront perdues. Le moteur en marche sera arrêté.")
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
            alert.messageText = String(localized: "Le moteur tourne.")
            alert.informativeText = reason == .quit
                ? String(localized: "Quitter l'application l'arrête.")
                : String(localized: "Fermer la fenêtre l'arrête et quitte l'application.")
            alert.addButton(withTitle: reason == .quit ? String(localized: "Arrêter et quitter") : String(localized: "Arrêter et fermer"))
            alert.addButton(withTitle: String(localized: "Annuler")).keyEquivalent = "\u{1b}"
            guard alert.runModal() == .alertFirstButtonReturn else { return false }
        }
        // Closing the window quits the application: it must not ask again.
        if reason == .close { leavingConfirmed = true }
        return true
    }
}

/// Asks before the window closes, as the system does for a document: a close that would lose changes, or stop the engine, is held until it is said.
/// The delegate of the window stays the one SwiftUI gave it: this one answers `windowShouldClose` and passes everything else on.
struct LeavingGuard: NSViewRepresentable {
    let model: AppModel

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { Anchor(coordinator: context.coordinator, model: model) }
    func updateNSView(_ view: NSView, context: Context) {}

    final class Coordinator { var proxy: Proxy? }

    @MainActor final class Proxy: NSObject, NSWindowDelegate {
        weak var original: NSWindowDelegate?
        let shouldClose: @MainActor () -> Bool

        init(shouldClose: @escaping @MainActor () -> Bool) { self.shouldClose = shouldClose }

        override func responds(to selector: Selector!) -> Bool { super.responds(to: selector) || (original?.responds(to: selector) ?? false) }
        override func forwardingTarget(for selector: Selector!) -> Any? {
            if original?.responds(to: selector) == true { return original }
            return super.forwardingTarget(for: selector)
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            guard shouldClose() else { return false }
            return original?.windowShouldClose?(sender) ?? true
        }
    }

    private final class Anchor: NSView {
        let coordinator: Coordinator
        let model: AppModel

        init(coordinator: Coordinator, model: AppModel) {
            self.coordinator = coordinator
            self.model = model
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError() }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, coordinator.proxy == nil else { return }
            let model = model
            let proxy = Proxy { model.confirmLeaving(.close) }
            proxy.original = window.delegate
            coordinator.proxy = proxy
            window.delegate = proxy
        }
    }
}
