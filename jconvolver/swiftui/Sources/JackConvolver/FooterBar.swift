// SPDX-License-Identifier: GPL-3.0-or-later

import AppearanceKit
import JConvolverKit
import MatrixKit
import SwiftUI

/// The same on every page: under the sidebar and the page, over the whole width of the window, 98 points high. On the left, two chips side
/// by side (the state, the mode); in the middle the round button; on the right the command line.
struct FooterBar: View {
    var body: some View {
        HStack {
            StatusColumn().frame(maxWidth: .infinity, alignment: .leading)
            RoundButton()
            CommandColumn().frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 24)
        .frame(height: 98)
        .background(Color.windowFill)
        .overlay(alignment: .top) { Divider() }
    }
}

/// On the left: the state and the mode in chips, and the load while the engine runs. What the configuration holds is in the card of the sidebar.
struct StatusColumn: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 8) {
            StatusPill()
            ModeChip()
            if model.controller.isRunning { LoadGauges().padding(.leading, 6) }
        }
        .frame(height: 28)
    }
}

/// The mode, said as the state is: a chip of information (the mode is chosen on the home page).
struct ModeChip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: model.mode == .file ? "waveform.path" : "dot.radiowaves.left.and.right").foregroundStyle(.secondary)
            Text(model.mode == .file ? "Sur fichier audio" : "Temps réel")
        }
        .font(.callout)
        .padding(.horizontal, 12).frame(height: 28)
        .background(Color.primary.opacity(0.07), in: Capsule())
        .help("Le mode se choisit sur la page d'accueil")
    }
}

struct StatusPill: View {
    @Environment(AppModel.self) private var model

    private enum Kind { case ready, running, warning, error }

    private var content: (kind: Kind, symbol: String, text: LocalizedStringKey) {
        let c = model.controller
        switch c.state {
        case .running: return (.running, "checkmark.circle.fill", model.mode == .file ? "Traitement…" : "En marche")
        case .stopping: return (.running, "checkmark.circle.fill", "Arrêt…")
        case .ended where c.endedOnAProblem: return (.error, "exclamationmark.circle.fill", "Le moteur s'est arrêté")
        default: break
        }
        guard model.isOpen else { return (.ready, "circle", "Aucune configuration ouverte") }
        let count = model.problems.count
        let toFix: LocalizedStringKey = count == 1 ? "1 problème à régler" : "\(count) problèmes à régler"
        if model.hasErrors { return (.error, "exclamationmark.circle.fill", toFix) }
        if count > 0 { return (.warning, "exclamationmark.triangle.fill", toFix) }
        return (.ready, "checkmark.circle.fill", model.mode == .file ? "Prêt à traiter" : "Prêt à lancer")
    }

    var body: some View {
        let state = content
        let color: Color = switch state.kind { case .ready, .running: .green; case .warning: .orange; case .error: .red }
        Button {
            // The pill says what is wrong: the problems to settle open their list; the log opens when the engine stopped on a problem.
            if model.controller.endedOnAProblem { model.page = .log } else if !model.problems.isEmpty { model.showsProblems = true }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: state.symbol).foregroundStyle(color)
                Text(state.text)
            }
            .font(.callout)
            .padding(.horizontal, 12).frame(height: 28)
            .background(state.kind == .ready ? Color.primary.opacity(0.07) : color.opacity(0.16), in: Capsule())
        }
        .buttonStyle(.plain)
        .opacity(model.isOpen || model.controller.isRunning ? 1 : 0.6)
    }
}

/// The load of the engine over the whole machine, and the audio cuts. A click on the cuts opens the journal.
struct LoadGauges: View {
    @Environment(AppModel.self) private var model
    @Environment(\.appAccentColor) private var accent

    var body: some View {
        let controller = model.controller
        HStack(spacing: 12) {
            let share = controller.machineShare ?? 0
            HStack(spacing: 5) {
                Text("Moteur").foregroundStyle(.secondary)
                ProgressView(value: min(1, share)).progressViewStyle(.linear).frame(width: 46).tint(accent)
                Text(verbatim: share < 0.01 ? "< 1 %" : "\(Int((share * 100).rounded())) %").monospacedDigit()
            }
            .help(helpText(controller))
            Button { model.page = .log } label: {
                HStack(spacing: 5) {
                    Text("xruns").foregroundStyle(.secondary)
                    Text(verbatim: "\(controller.xruns)").monospacedDigit().foregroundStyle(controller.xruns > 0 ? Color.red : Color.primary)
                }
            }
            .buttonStyle(.plain)
            .help("Coupures audio depuis le lancement. Cliquer pour voir le journal.")
        }
        .font(.caption)
    }

    private func helpText(_ controller: EngineController) -> LocalizedStringKey {
        let cores = controller.cores ?? 0
        let all = ProcessInfo.processInfo.activeProcessorCount
        return "CPU du moteur : \(cores.formatted(.number.precision(.fractionLength(1)))) cœur sur \(all)"
    }
}

/// The round button: starts the engine, stops it while it runs.
struct RoundButton: View {
    @Environment(AppModel.self) private var model
    @Environment(\.appAccentColor) private var accent
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let running = model.controller.isRunning
        let blocked = !model.isOpen || (!running && model.hasErrors)
        Button { model.toggleRun() } label: {
            Image(systemName: running ? "stop.fill" : "star.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 62, height: 62)
                .accentGlassDisc(accent)
        }
        .buttonStyle(PressStyle())
        .disabled(blocked)
        .opacity(blocked ? 0.5 : 1)
        .help(running ? "Arrêter" : (model.hasErrors ? "Il reste des points à régler" : "Lancer"))
    }
}

/// On the right: the command line, a button as in the other applications of the collection.
struct CommandColumn: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button("Ligne de commande générée") { model.showsCommand = true }
            .disabled(!model.isOpen)
    }
}
