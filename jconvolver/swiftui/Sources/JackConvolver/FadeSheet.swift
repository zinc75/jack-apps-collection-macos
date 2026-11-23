// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import AppearanceKit
import JConvolverKit
import SwiftUI

/// Applying a fade: a new audio file is written with the part of the response that is read, windowed, and the configuration reads it instead of the
/// original, which is not changed.
struct FadeSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var context: FadeContext?
    @State private var name = ""
    @State private var folder: URL?
    /// Whether the folder is the one that is made for this fade (next to the original), or one that the person chose.
    @State private var chosen = false
    @State private var working = false
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Appliquer le fondu").font(.title3).fontWeight(.semibold)
                Text("Un nouveau fichier audio est écrit avec le fondu, et la configuration le lira à la place de « \(context.map { ($0.path as NSString).lastPathComponent } ?? "") ». Le fichier d'origine n'est pas modifié.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let context { form(context) } else {
                Text("Cette réponse ne peut pas recevoir de fondu.").foregroundStyle(.secondary)
                HStack { Spacer(); Button("Fermer") { dismiss() }.keyboardShortcut(.defaultAction) }
            }
        }
        .padding(22).frame(width: 640)
        .onAppear {
            guard let made = model.fadeContext() else { return }
            context = made
            name = (model.fadeFileName(made) as NSString).deletingPathExtension
            folder = model.fadeDefaultFolder(made)
        }
    }

    private func form(_ context: FadeContext) -> some View {
        let ext = ImpulseFade.output(for: context.info).fileExtension
        let destination = folder?.appendingPathComponent(name + "." + ext)
        let taken = destination.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                row("Nom") {
                    HStack(spacing: 8) {
                        TextField("", text: $name).textFieldStyle(.roundedBorder)
                            .onChange(of: name) { _, new in
                                let cleaned = PortableOptions.cleaned(new)
                                if cleaned != new { name = cleaned }
                            }
                        Text(verbatim: "." + ext).font(.caption).foregroundStyle(.secondary).fixedSize()
                    }
                }
                row("Dossier", note: chosen ? nil : String(localized: "Un dossier est créé à côté de l'original pour ce fondu.")) {
                    HStack(spacing: 10) {
                        Button("Choisir…") { chooseFolder(context) }
                        Text(verbatim: folder?.path ?? "").font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.head).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            if !context.others.isEmpty {
                Text(others(context)).font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: name + "." + ext).font(.system(.callout, design: .monospaced)).fontWeight(.semibold)
                Text("1 voie · \(context.length) échantillons (\((Double(context.length) / max(context.info.sampleRate, 1) * 1000).formatted(.number.precision(.fractionLength(0...1)))) ms) · même format que l'original · fondu de \(context.fadeIn) éch. à la montée, \(context.fadeOut) éch. à la descente")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            if taken { Label("Ce nom est déjà pris : choisissez-en un autre.", systemImage: "exclamationmark.triangle.fill").foregroundStyle(Color.alert).font(.callout) }
            if let failure { Label(failure, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Color.alert).font(.callout) }
            HStack {
                if working { ProgressView().controlSize(.small); Text("Écriture…").font(.callout).foregroundStyle(.secondary) }
                Spacer()
                Button("Annuler", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction).disabled(working)
                Button("Créer le fichier") { create(context, ext: ext) }
                    .buttonStyle(.borderedProminent).accentTint().keyboardShortcut(.defaultAction)
                    .disabled(working || taken || name.trimmingCharacters(in: .whitespaces).isEmpty || folder == nil)
            }
        }
    }

    private func row<Content: View>(_ title: LocalizedStringKey, note: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(title).frame(width: 70, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                content()
                if let note { Text(verbatim: note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The other responses that read the same voie of the same file keep the original: said, without asking.
    private func others(_ context: FadeContext) -> String {
        let names = context.others.prefix(3).map { model.traceFullName($0) }.joined(separator: ", ")
        let more = context.others.count > 3 ? String(localized: " et \(context.others.count - 3) autre(s)") : ""
        let file = (context.path as NSString).lastPathComponent
        return context.others.count == 1
            ? String(localized: "La voie \(context.channel) de \(file) est aussi utilisée par une autre réponse (\(names)). Elle garde le fichier d'origine : seule celle-ci utilisera le nouveau fichier.")
            : String(localized: "La voie \(context.channel) de \(file) est aussi utilisée par \(context.others.count) autres réponses (\(names)\(more)). Elles gardent le fichier d'origine : seule celle-ci utilisera le nouveau fichier.")
    }

    private func chooseFolder(_ context: FadeContext) {
        guard let url = model.chooseFadeFolder(near: context.path) else { return }
        folder = url
        chosen = true
    }

    private func create(_ context: FadeContext, ext: String) {
        guard let folder else { return }
        working = true
        failure = nil
        let destination = folder.appendingPathComponent(name + "." + ext)
        Task {
            do {
                try await model.applyFade(context, to: destination)
                dismiss()
            } catch {
                working = false
                failure = describe(error)
                // A folder where nothing can be written (a read-only volume): another one is asked for.
                if case ImpulseFadeError.cannotWrite = error { chosen = false }
            }
        }
    }

    private func describe(_ error: Error) -> String {
        switch error as? ImpulseFadeError {
        case .cannotRead(let reason): String(localized: "Le fichier ne peut pas être lu : \(reason)")
        case .channelMissing: String(localized: "La voie n'existe plus dans le fichier.")
        case .emptyZone: String(localized: "La partie lue du fichier est vide.")
        case .cannotWrite(let reason): String(localized: "Le fichier ne peut pas être écrit ici : \(reason). Choisissez un autre dossier.")
        case .none: error.localizedDescription
        }
    }
}
