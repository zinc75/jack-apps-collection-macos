// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import AppearanceKit
import JConvolverKit
import MatrixKit
import SwiftUI

/// What the engine writes, what JACK reports, what the application did.
struct LogView: View {
    @Environment(AppModel.self) private var model
    @State private var onlyProblems = false
    @State private var follows = true

    private var log: EngineLog { model.controller.log }
    private var timeFormat: Date.FormatStyle { Date.FormatStyle().hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Journal du moteur").font(.title2).fontWeight(.semibold)
                Text(summary).font(.callout).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Picker("Filtre", selection: $onlyProblems) {
                    Text("Tout").tag(false)
                    Text("Avertissements et erreurs").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                Spacer()
                Button("Copier") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(log.plainText(onlyProblems: onlyProblems), forType: .string)
                }
                Button("Effacer") { model.controller.clearLog() }
                Toggle("Suivre la fin", isOn: $follows).toggleStyle(.switch).controlSize(.small).accentTint()
            }
            entries
        }
        .padding(24)
        .onAppear { model.markLogSeen() }
        .onChange(of: log.entries.count) { _, _ in model.markLogSeen() }
    }

    private var summary: String {
        let c = model.controller
        let program = model.mode == .file ? "fconvolver" : "jconvolver"
        let state: String = switch c.state {
        case .running, .stopping: String(localized: "en marche")
        case .ended where c.endedOnAProblem: String(localized: "arrêté sur une erreur")
        default: String(localized: "arrêté")
        }
        return "\(program) · \(state) · " + String(localized: "\(log.warningCount) avertissement(s)") + " · " + String(localized: "\(log.errorCount) erreur(s)")
    }

    private var entries: some View {
        let shown = log.entries(onlyProblems: onlyProblems)
        return ScrollViewReader { proxy in
            ScrollView {
                if shown.isEmpty {
                    Text(log.entries.isEmpty ? "Rien pour l'instant : le journal se remplit au lancement du moteur." : "Aucun avertissement ni erreur.")
                        .foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 56)
                } else {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(shown) { entry in
                            row(entry).id(entry.id)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .blockBackground()
            .onChange(of: shown.last?.id) { _, last in
                if follows, let last { proxy.scrollTo(last, anchor: .bottom) }
            }
        }
    }

    private func row(_ entry: EngineLogEntry) -> some View {
        let color: Color = switch entry.severity { case .info: .primary; case .warning: .orange; case .error: .red }
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(entry.date.formatted(timeFormat)).foregroundStyle(.tertiary)
            Text(entry.source.rawValue).foregroundStyle(.secondary).frame(width: 52, alignment: .leading)
            Text(entry.display).foregroundStyle(entry.startsRun ? Color.primary : color).fontWeight(entry.startsRun ? .semibold : .regular)
                .textSelection(.enabled)
        }
        .font(.system(size: 12, design: .monospaced))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 1)
        .padding(.top, entry.startsRun ? 8 : 0)
    }
}
