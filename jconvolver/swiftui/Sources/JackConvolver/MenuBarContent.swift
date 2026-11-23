// SPDX-License-Identifier: GPL-3.0-or-later

import AppearanceKit
import SwiftUI

/// The panel of the icon in the menu bar: one row for each session, with what it is doing and the buttons to bring its window back, to start or stop its
/// engine, or to close it, and quitting at the bottom.
struct MenuBarContent: View {
    let hub: AppHub
    @Environment(\.openWindow) private var openWindow
    @Environment(\.appAccentColor) private var accent

    var body: some View {
        // The scene of the icon knows how to open a window, also when none is open.
        let _ = { hub.openWindowAction = { openWindow(value: $0) }; hub.openSessionsAction = { openWindow(id: "sessions") } }()
        VStack(alignment: .leading, spacing: 2) {
            ForEach(hub.shownSessions, id: \.id) { session in
                MenuBarRow(hub: hub, session: session)
            }
            Divider().padding(.vertical, 4)
            if !hub.shownSessions.isEmpty {
                Button { hub.showAllWindows() } label: {
                    HStack {
                        Label("Tout afficher", systemImage: "macwindow.on.rectangle")
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10).padding(.vertical, 5)
            }
            Button { hub.newSession() } label: {
                HStack {
                    Label("Nouvelle session", systemImage: "plus.circle")
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10).padding(.vertical, 5)
            Button { NSApp.terminate(nil) } label: {
                HStack {
                    Text("Quitter Jack Convolver")
                    Spacer()
                    Text("⌘Q").foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q")
            .padding(.horizontal, 10).padding(.vertical, 5)
        }
        .padding(8)
        .frame(width: 340)
    }
}

/// A session in the panel: a dot that says whether its engine runs, its name and what it is doing, and its buttons.
private struct MenuBarRow: View {
    let hub: AppHub
    let session: AppModel
    @Environment(\.appAccentColor) private var accent
    @State private var hovered = false

    var body: some View {
        let running = session.controller.isRunning
        HStack(spacing: 10) {
            Circle().fill(running ? Color.green : Color.secondary.opacity(0.4)).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: session.displayName + (session.isCopy ? " (" + String(localized: "copie") + ")" : "")).lineLimit(1).truncationMode(.middle)
                Text(verbatim: Self.state(of: session)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            // The window: brought back, or opened again when it was closed while the engine went on.
            glyph("macwindow", help: String(localized: "Afficher la fenêtre")) { hub.showWindow(of: session) }
            if session.mode == .realTime {
                glyph(running ? "stop.fill" : "play.fill", help: running ? String(localized: "Arrêter le moteur") : String(localized: "Lancer le moteur"),
                      enabled: session.isOpen && (running || !session.hasErrors)) { session.toggleRun() }
            }
            if session.isWindowHidden, !running {
                glyph("xmark", help: String(localized: "Fermer la session")) { hub.discard(session) }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.primary.opacity(hovered ? 0.08 : 0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { hovered = $0 }
    }

    private func glyph(_ name: String, help: String, enabled: Bool = true, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).font(.system(size: 13, weight: .semibold))
                .frame(width: 26, height: 24)
                .background(Color.primary.opacity(0.08), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .help(help)
    }

    /// What the session is doing, in a few words.
    static func state(of session: AppModel) -> String {
        let c = session.controller
        if c.isRunning {
            if session.mode == .file { return String(localized: "traitement en cours") }
            // The name JACK gave its client, to find it in the patchbay (not known for the first instants of a run).
            let running = String(localized: "moteur en cours d'exécution")
            return session.runClientName.map { running + " · " + $0 } ?? running
        }
        if c.endedOnAProblem { return String(localized: "moteur arrêté sur une erreur") }
        return session.isOpen ? String(localized: "en configuration") : String(localized: "aucune configuration ouverte")
    }
}
