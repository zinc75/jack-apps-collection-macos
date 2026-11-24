// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import AppearanceKit
import JConvolverKit
import SwiftUI

/// Exports a configuration as a portable version: one audio file with every impulse response and a new configuration file that refers to it, to be
/// sent as they are. The files of the original are not changed.
struct PortableExportSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var options = PortableOptions(name: "")
    @State private var folder: URL?
    @State private var plan: PortablePlan?
    @State private var working = false
    @State private var result: PortableResult?
    @State private var failure: String?

    private static let folderKey = "portableFolder"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Exporter en version portable").font(.title3).fontWeight(.semibold)
                Text("Un fichier audio avec toutes les réponses impulsionnelles et un fichier de configuration qui s'y réfère, à envoyer tels quels. Vos fichiers d'origine ne sont pas modifiés.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let result { done(result) } else { form }
        }
        .padding(22).frame(width: 680)
        .onAppear {
            options.name = model.portableDefaultName
            folder = savedFolder() ?? URL(fileURLWithPath: model.configDirectory)
            refresh()
        }
        .onChange(of: options) { _, _ in refresh() }
    }

    // MARK: The form

    private var form: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let plan {
                Text(summary(plan)).font(.callout).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 12) {
                row("Nom") {
                    HStack(spacing: 8) {
                        TextField("", text: Binding(get: { options.name }, set: { options.name = PortableOptions.cleaned($0) }))
                            .textFieldStyle(.roundedBorder)
                        Text(verbatim: "." + (plan?.requiresCAF == true ? "caf" : options.container.rawValue) + " / .conf" + (options.output == .files ? "" : " / .zip"))
                            .font(.caption).foregroundStyle(.secondary).fixedSize()
                    }
                }
                row("Dossier") {
                    HStack(spacing: 10) {
                        Button("Choisir…") { chooseFolder() }
                        Text(verbatim: folder?.path ?? "").font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.head).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                row("Format audio", note: plan?.requiresCAF == true ? String(localized: "Le fichier dépasse 4 Go : seul le format CAF convient.")
                                                                    : String(localized: "WAV se lit partout ; CAF n'a pas de limite de taille.")) {
                    Picker("", selection: $options.container) {
                        Text("WAV").tag(PortableOptions.Container.wav).disabled(plan?.requiresCAF == true)
                        Text("CAF").tag(PortableOptions.Container.caf)
                    }
                    .pickerStyle(.segmented).labelsHidden().accentTint()
                }
                row("Précision", note: options.precision == .source ? plan.map { precisionName($0) } : nil) {
                    Picker("", selection: $options.precision) {
                        Text("Comme l'original").tag(PortableOptions.Precision.source)
                        Text("32 bits flottants").tag(PortableOptions.Precision.float32)
                    }
                    .pickerStyle(.segmented).labelsHidden().accentTint()
                }
                row("Sortie") {
                    Picker("", selection: $options.output) {
                        Text("Deux fichiers").tag(PortableOptions.Output.files)
                        Text("Fichiers et .zip").tag(PortableOptions.Output.filesAndArchive)
                        Text("Archive .zip seule").tag(PortableOptions.Output.archiveOnly)
                    }
                    .pickerStyle(.segmented).labelsHidden().accentTint()
                }
            }
            Toggle(isOn: $options.appliesSettings) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Écrire les réglages dans le fichier audio")
                    Text("Gain, retard, début et longueur sont appliqués aux échantillons : plus simple à utiliser ailleurs, mais ces réglages ne se modifient plus et le fichier audio est plus lourd, car il contient aussi le retard de chaque réponse.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch).accentTint()
            preview
            if let plan, plan.isBlocked { blockers(plan) }
            if let failure { Label(failure, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Color.alert).font(.callout) }
            HStack {
                if working { ProgressView().controlSize(.small); Text("Écriture…").font(.callout).foregroundStyle(.secondary) }
                Spacer()
                Button("Annuler", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction).disabled(working)
                Button("Exporter") { export() }
                    .buttonStyle(.borderedProminent).accentTint().keyboardShortcut(.defaultAction)
                    .disabled(working || plan == nil || plan?.isBlocked == true || folder == nil)
            }
        }
    }

    /// A line of the form: the name of the setting at the left, its control at the right, a note under the control.
    private func row<Content: View>(_ title: LocalizedStringKey, note: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(title).frame(width: 96, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                content()
                if let note { Text(verbatim: note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let plan, let rate = plan.sampleRate {
                let ext = plan.requiresCAF ? "caf" : options.container.rawValue
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "\(options.name).\(ext)").font(.system(.callout, design: .monospaced)).fontWeight(.semibold)
                    Text("\(plan.channels) voies · \(plan.frames) échantillons (\((Double(plan.frames) / rate * 1000).formatted(.number.precision(.fractionLength(0...1)))) ms) · \(size(plan.audioBytes))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "\(options.name).conf").font(.system(.callout, design: .monospaced)).fontWeight(.semibold)
                    Text("fichier de configuration, \(plan.configLines) lignes").font(.caption).foregroundStyle(.secondary)
                }
                if options.output != .files {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "\(options.name).zip").font(.system(.callout, design: .monospaced)).fontWeight(.semibold)
                        Text(options.output == .archiveOnly ? "les deux fichiers, seuls dans le dossier" : "les deux fichiers dans une archive, qui s'ajoute à eux")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Rien à regrouper pour l'instant.").font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func blockers(_ plan: PortablePlan) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(plan.blockers.enumerated()), id: \.offset) { _, blocker in
                Label(text(for: blocker), systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(Color.alert)
            }
        }
    }

    // MARK: Done

    private func done(_ result: PortableResult) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            let written = [result.audio, result.configuration, result.archive].compactMap { $0 }
            Label(written.count == 1 ? "Un fichier écrit dans « \(folder?.lastPathComponent ?? "") »." : "\(written.count) fichiers écrits dans « \(folder?.lastPathComponent ?? "") ».",
                  systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 3) {
                ForEach(written, id: \.self) { Text(verbatim: $0.lastPathComponent).font(.system(.callout, design: .monospaced)) }
            }
            HStack {
                Spacer()
                Button("Afficher dans le Finder") { NSWorkspace.shared.activateFileViewerSelecting(written) }
                Button("Fermer") { dismiss() }.buttonStyle(.borderedProminent).accentTint().keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: Actions

    private func refresh() {
        failure = nil
        guard !working else { return }
        var made = options
        let planned = model.portablePlan(made)
        // A file over 4 GB cannot be a WAV file.
        if planned?.requiresCAF == true, made.container == .wav { made.container = .caf; options = made; return }
        plan = planned
    }

    private func savedFolder() -> URL? {
        guard let path = UserDefaults.standard.string(forKey: Self.folderKey), FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = String(localized: "Choisir")
        panel.directoryURL = folder
        guard panel.runModal() == .OK, let url = panel.url else { return }
        folder = url
        UserDefaults.standard.set(url.path, forKey: Self.folderKey)
    }

    private func export() {
        guard let plan, let folder else { return }
        // What would be replaced is said first.
        let existing = PortableExporter.targets(plan: plan, options: options, in: folder).filter { FileManager.default.fileExists(atPath: $0.path) }
        if !existing.isEmpty {
            let alert = NSAlert()
            alert.messageText = existing.count == 1 ? String(localized: "« \(existing[0].lastPathComponent) » existe déjà dans ce dossier.")
                                                    : String(localized: "\(existing.count) fichiers existent déjà dans ce dossier.")
            alert.informativeText = existing.map(\.lastPathComponent).joined(separator: "\n") + "\n\n" + String(localized: "Les remplacer ?")
            alert.addButton(withTitle: String(localized: "Remplacer"))
            alert.addButton(withTitle: String(localized: "Annuler"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        working = true
        failure = nil
        let chosen = options
        Task {
            do {
                result = try await model.exportPortable(chosen, to: folder)
            } catch {
                failure = describe(error)
            }
            working = false
        }
    }

    // MARK: Words

    private func summary(_ plan: PortablePlan) -> String {
        let impulses = plan.impulses == 1 ? String(localized: "1 réponse placée") : String(localized: "\(plan.impulses) réponses placées")
        let files = plan.files == 1 ? String(localized: "1 fichier") : String(localized: "\(plan.files) fichiers")
        var line = String(localized: "\(impulses), prises dans \(files)")
        if plan.folders > 1 { line += String(localized: " de \(plan.folders) dossiers") }
        line += "."
        if !options.appliesSettings { line += " " + String(localized: "Une réponse utilisée à plusieurs endroits n'est écrite qu'une fois.") }
        return line
    }

    private func precisionName(_ plan: PortablePlan) -> String {
        switch plan.bytesPerSample {
        case 2: String(localized: "16 bits ici")
        case 3: String(localized: "24 bits ici")
        default: plan.subtype == 0x0002 ? String(localized: "32 bits ici") : String(localized: "32 bits flottants ici")
        }
    }

    private func size(_ bytes: Int) -> String {
        // The units are the French ones in the source, and written GB, MB and kB in the other languages.
        bytes >= 1_000_000_000 ? String(localized: "\((Double(bytes) / 1e9).formatted(.number.precision(.fractionLength(2)))) Go")
            : bytes >= 1_000_000 ? String(localized: "\((Double(bytes) / 1e6).formatted(.number.precision(.fractionLength(1)))) Mo")
            : String(localized: "\(max(1, bytes / 1000)) Ko")
    }

    private func text(for blocker: PortableBlocker) -> String {
        switch blocker {
        case .noFileImpulse: String(localized: "Aucune réponse ne vient d'un fichier : il n'y a rien à regrouper.")
        case .fileMissing(let path): String(localized: "Fichier introuvable : \((path as NSString).lastPathComponent). Corrigez-le d'abord (voir « à régler »).")
        case .channelMissing(let path, let channel, let channels):
            String(localized: "La voie \(channel) n'existe pas dans \((path as NSString).lastPathComponent) (voies : \(channels)).")
        case .differentRates(let rates):
            String(localized: "Les fichiers n'ont pas tous la même fréquence (\(rates.map { Int($0).formatted() }.joined(separator: ", ")) Hz) : un fichier audio n'en a qu'une. Convertissez-les d'abord.")
        case .emptyName: String(localized: "Le nom est vide.")
        }
    }

    private func describe(_ error: Error) -> String {
        switch error as? PortableError {
        case .cannotRead(let path): String(localized: "Un fichier ne peut pas être lu : \(path)")
        case .tooLarge: String(localized: "Les fichiers sont trop gros pour être regroupés en mémoire.")
        case .cannotWrite(let reason): String(localized: "Les fichiers ne peuvent pas être écrits : \(reason)")
        case .archiveFailed(let reason): String(localized: "L'archive ne peut pas être faite : \(reason)")
        case .blocked, .none: error.localizedDescription
        }
    }
}
