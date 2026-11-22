// SPDX-License-Identifier: GPL-3.0-or-later

import AppearanceKit
import JConvolverKit
import MatrixKit
import SwiftUI

/// The same on every page: under the sidebar and the page, over the whole width of the window, 98 points high.
struct FooterBar: View {
    var body: some View {
        HStack {
            StatusColumn().frame(maxWidth: .infinity, alignment: .leading)
            RoundButton()
            ModeColumn().frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 24)
        .frame(height: 98)
        .background(Color.windowFill)
        .overlay(alignment: .top) { Divider() }
    }
}

/// On the left: the state in a pill, the load while the engine runs, and the configuration that is open.
struct StatusColumn: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                StatusPill()
                if model.controller.isRunning { LoadGauges() }
            }
            if model.isOpen { ConfigurationName() }
        }
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

/// The name of the configuration, a dot while it has changes that are not saved, and its size.
struct ConfigurationName: View {
    @Environment(AppModel.self) private var model
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 6) {
            // In the normal text colour, so that it reads on the dark footer; it is underlined under the pointer, as a link.
            Button { model.page = .matrix } label: {
                Text(model.name).underline(hovered).lineLimit(1).truncationMode(.middle)
            }
            .buttonStyle(.plain)
            .onHover { hovered = $0 }
            .help("Voir la configuration")
            if model.isEdited { Circle().fill(Color.orange).frame(width: 7, height: 7).help("Modifié, pas encore enregistré (⌘S)") }
            if let d = model.document { Text(verbatim: "· \(d.inputCount) × \(d.outputCount)").foregroundStyle(.secondary).fixedSize() }
        }
        .font(.caption)
        .frame(maxWidth: 320, alignment: .leading)
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

/// On the right: real time or sound files, and the command line.
struct ModeColumn: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .trailing, spacing: 8) {
            Picker("Mode", selection: $model.mode) {
                Text("Temps réel").tag(RunMode.realTime)
                Text("Sur fichier audio").tag(RunMode.file)
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize().accentTint()
            .disabled(model.controller.isRunning)
            Button("Ligne de commande générée") { model.showsCommand = true }
                .disabled(!model.isOpen)
        }
    }
}
