// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import AppearanceKit
import MatrixKit
import SwiftUI

/// The window of the sessions, what the click on the Dock leads to when several of them have no window: a card for each, with what it does and the
/// buttons to bring its window back, to start or stop its engine, or to close it.
struct SessionsWindowView: View {
    let hub: AppHub
    @Environment(\.openWindow) private var openWindow
    @Environment(\.appAccentColor) private var accent

    var body: some View {
        // The scene knows how to open a window, also when none is open.
        let _ = { hub.openWindowAction = { openWindow(value: $0) }; hub.openSessionsAction = { openWindow(id: "sessions") } }()
        let sessions = hub.shownSessions
        let running = sessions.filter { $0.controller.isRunning }.count
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sessions").font(.title2).fontWeight(.semibold)
                    Text(summary(sessions: sessions.count, running: running)).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if let load = hub.jack.cpuLoad, running > 0 {
                    Chip(text: Text("JACK \(Int(load.rounded())) %"), kind: load >= 90 ? .bad : load >= 70 ? .warn : .plain, symbol: "waveform.path.ecg")
                }
            }
            .padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 12)

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(sessions, id: \.id) { SessionCard(hub: hub, session: $0) }
                }
                .padding(.horizontal, 22).padding(.vertical, 4)
            }

            HStack(spacing: 8) {
                SessionsButton("Nouvelle session", symbol: "plus") { hub.newSession() }
                SessionsButton("Ouvrir…", symbol: "folder") { hub.openInNewSession() }
                SessionsButton("Tout afficher", symbol: "macwindow.on.rectangle") { hub.showAllWindows() }
                    .disabled(sessions.isEmpty)
                Spacer()
                SessionsButton("Quitter") { NSApp.terminate(nil) }
            }
            .padding(.horizontal, 22).padding(.vertical, 14)
            .overlay(alignment: .top) { Divider() }
        }
        .frame(minWidth: 640, minHeight: 360)
    }

    private func summary(sessions: Int, running: Int) -> String {
        let s = sessions == 1 ? String(localized: "1 session") : String(localized: "\(sessions) sessions")
        let r = running == 0 ? String(localized: "aucun moteur en cours d'exécution")
            : running == 1 ? String(localized: "1 moteur en cours d'exécution") : String(localized: "\(running) moteurs en cours d'exécution")
        return s + ", " + r
    }
}

/// A session in the window of the sessions.
private struct SessionCard: View {
    let hub: AppHub
    let session: AppModel
    @Environment(\.appAccentColor) private var accent

    var body: some View {
        let c = session.controller
        let running = c.isRunning
        let failed = c.endedOnAProblem
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(running ? Color.green.opacity(0.18) : failed ? Color.red.opacity(0.18) : Color.primary.opacity(0.08))
                Image(systemName: running ? "play.fill" : failed ? "exclamationmark" : "gearshape")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(running ? Color.green : failed ? Color.red : Color.secondary)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(verbatim: session.displayName + (session.isCopy ? " (" + String(localized: "copie") + ")" : ""))
                        .font(.system(size: 14, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                    if session.isEdited { Text("Modifié").font(.caption).foregroundStyle(.orange) }
                }
                Text(verbatim: details).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 14) {
                    if running, session.mode == .realTime, let name = session.runClientName {
                        Chip(text: Text(verbatim: name), kind: .plain, symbol: "cable.connector")
                    }
                    if running {
                        HStack(spacing: 6) {
                            Text("Moteur").foregroundStyle(.secondary)
                            ProgressView(value: min(1, c.machineShare ?? 0)).progressViewStyle(.linear).frame(width: 54).tint(accent)
                            Text(verbatim: percent(c.machineShare ?? 0)).monospacedDigit()
                        }
                        .font(.caption)
                        Text("xruns \(c.xruns)").font(.caption).monospacedDigit().foregroundStyle(c.xruns > 0 ? Color.red : Color.secondary)
                    } else {
                        Text(verbatim: stateText).font(.caption).foregroundStyle(failed ? Color.red : Color.secondary)
                    }
                }
                .padding(.top, 3)
            }
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                SessionsButton("Afficher", symbol: "macwindow", prominent: running) { hub.showWindow(of: session) }
                if session.mode == .realTime {
                    SessionsGlyph(running ? "stop.fill" : "play.fill", help: running ? String(localized: "Arrêter le moteur") : String(localized: "Lancer le moteur"),
                                  enabled: session.isOpen && (running || !session.hasErrors)) { session.toggleRun() }
                }
                if session.isWindowHidden, !running {
                    SessionsGlyph("xmark", help: String(localized: "Fermer la session")) { hub.discard(session) }
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 14, interactive: false, selected: running)
    }

    /// What the configuration holds, in a line.
    private var details: String {
        guard let d = session.document else { return String(localized: "Aucune configuration ouverte") }
        let inputs = d.inputCount == 1 ? String(localized: "1 entrée") : String(localized: "\(d.inputCount) entrées")
        let outputs = d.outputCount == 1 ? String(localized: "1 sortie") : String(localized: "\(d.outputCount) sorties")
        let n = d.placedPairs
        let responses = n == 0 ? String(localized: "aucune réponse impulsionnelle") : n == 1 ? String(localized: "1 réponse impulsionnelle") : String(localized: "\(n) réponses impulsionnelles")
        return "\(inputs) · \(outputs) · \(responses)"
    }

    private var stateText: String {
        if session.controller.endedOnAProblem { return String(localized: "Moteur arrêté sur une erreur") }
        return session.isWindowHidden ? String(localized: "En configuration, fenêtre non affichée") : String(localized: "En configuration")
    }

    private func percent(_ share: Double) -> String { share < 0.01 ? "< 1 %" : "\(Int((share * 100).rounded())) %" }
}

/// A capsule button of the window of the sessions; the one that is `prominent` takes the accent.
struct SessionsButton: View {
    let title: LocalizedStringKey
    var symbol: String?
    var prominent = false
    let action: () -> Void
    @Environment(\.appAccentColor) private var accent
    @Environment(\.isEnabled) private var isEnabled

    init(_ title: LocalizedStringKey, symbol: String? = nil, prominent: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.prominent = prominent
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.system(size: 12, weight: .semibold)) }
                Text(title).font(.system(size: 13, weight: prominent ? .semibold : .regular))
            }
            .padding(.horizontal, 13).frame(height: 30)
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .background(prominent ? accent : Color.primary.opacity(0.09), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(prominent ? 0 : 0.14), lineWidth: 0.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.4)
    }
}

/// A round button with a symbol only.
struct SessionsGlyph: View {
    let symbol: String
    let help: String
    var enabled = true
    let action: () -> Void

    init(_ symbol: String, help: String, enabled: Bool = true, action: @escaping () -> Void) {
        self.symbol = symbol
        self.help = help
        self.enabled = enabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(Color.primary.opacity(0.09), in: Circle())
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .help(help)
    }
}
