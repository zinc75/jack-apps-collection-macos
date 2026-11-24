// SPDX-License-Identifier: GPL-3.0-or-later

import JConvolverKit
import SwiftUI

/// Over the matrix, when files cannot be found and files of the same names are next to the configuration file: said, with the way to take them.
struct MissingFilesBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if !model.pathProposals.isEmpty {
            let found = model.pathProposals.reduce(0) { $0 + $1.found.count }
            HStack(spacing: 10) {
                Label(found == 1 ? "Un fichier introuvable existe ici, dans le dossier du fichier de configuration."
                                 : "\(found) fichiers introuvables existent ici, dans le dossier du fichier de configuration.",
                      systemImage: "folder.badge.questionmark")
                    .font(.callout).foregroundStyle(.orange).lineLimit(2)
                Spacer(minLength: 8)
                Button("Chercher…") { model.showsResolver = true }.controlSize(.small).disabled(model.isLocked)
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
    }
}

/// The folders where files that were not found are found again: what the configuration looked in, where the files of the same names are, and how many.
/// The person takes the ones they want; the configuration then names the files from its own folder, so that it does not depend on the machine.
struct ResolvePathsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @State private var chosen: Set<String> = []

    var body: some View {
        let proposals = model.pathProposals
        VStack(alignment: .leading, spacing: 14) {
            Text("Retrouver les fichiers").font(.title3).fontWeight(.semibold)
            Text("Des fichiers de mêmes noms sont dans le dossier du fichier de configuration : « \(model.configDirectory) ». Choisissez ceux à prendre ; la configuration les nommera à partir de son propre dossier.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(proposals) { proposal in
                        HStack(alignment: .top, spacing: 10) {
                            Toggle("", isOn: Binding(get: { chosen.contains(proposal.id) }, set: { on in
                                if on { chosen.insert(proposal.id) } else { chosen.remove(proposal.id) }
                            })).labelsHidden().toggleStyle(.checkbox).accentTint()
                            VStack(alignment: .leading, spacing: 3) {
                                Text(verbatim: proposal.from).font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                                Label(proposal.isInConfigurationFolder ? String(localized: "dans le dossier du fichier de configuration")
                                                                        : String(localized: "dans le dossier « \(proposal.to) »"), systemImage: "arrow.turn.down.right")
                                    .font(.callout)
                                Text(foundSummary(proposal))
                                    .font(.caption).foregroundStyle(.secondary)
                                if !proposal.missing.isEmpty {
                                    Text(verbatim: proposal.missing.prefix(4).joined(separator: ", ") + (proposal.missing.count > 4 ? "…" : ""))
                                        .font(.caption).foregroundStyle(.orange).lineLimit(2)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(10)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                }
            }
            .frame(maxHeight: 340)
            HStack {
                Spacer()
                Button("Annuler") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Appliquer") {
                    model.applyPathProposals(proposals.filter { chosen.contains($0.id) })
                    dismiss()
                }
                .buttonStyle(.borderedProminent).accentTint().keyboardShortcut(.defaultAction)
                .disabled(chosen.isEmpty)
            }
        }
        .padding(22).frame(width: 560)
        .onAppear { chosen = Set(model.pathProposals.map(\.id)) }
    }
}

extension AppModel {
    /// A file that cannot be found is replaced by one that the person chooses: every impulse response that uses it uses the new one (a name when
    /// the file is in the folder of the configuration or in one of its folders, else the full path), in one step of the history.
    func locateFile(missing path: String) {
        guard !isLocked else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: configDirectory)
        panel.message = String(localized: "Choisissez le fichier à utiliser à la place de « \((path as NSString).lastPathComponent) ».")
        panel.prompt = String(localized: "Utiliser ce fichier")
        guard panel.runModal() == .OK, let chosen = panel.url else { return }
        let configDirectory = self.configDirectory
        let base = URL(fileURLWithPath: configDirectory).standardizedFileURL.path + "/"
        let full = chosen.standardizedFileURL.path
        let replacement = full.hasPrefix(base) ? String(full.dropFirst(base.count)) : full
        edit(String(localized: "fichier choisi")) { document in
            for pair in document.content.impulses.keys.sorted() {
                for (index, impulse) in document.impulses(at: pair).enumerated() {
                    guard case .file(let file, let channel) = impulse.source,
                          ConvConfig.path(of: file, directory: impulse.directory, configDirectory: configDirectory) == path else { continue }
                    var changed = impulse
                    changed.source = .file(path: replacement, channel: channel)
                    changed.directory = nil
                    document.replace(changed, at: index, of: pair)
                }
            }
        }
        loadBin()
    }
}

/// "Sélectionner le fichier…": for a file that is not found, the person chooses the one to use instead.
struct LocateButton: View {
    @Environment(AppModel.self) private var model
    let path: String

    var body: some View {
        Button("Sélectionner le fichier…") { model.locateFile(missing: path) }
            .controlSize(.small).disabled(model.isLocked)
            .help("Choisir le fichier à utiliser à la place de celui qui est introuvable")
    }
}


/// "3 fichiers trouvés, 1 toujours introuvable", with the agreement of the language.
private func foundSummary(_ proposal: PathProposal) -> String {
    let found = proposal.found.count, missing = proposal.missing.count
    let first = found == 1 ? String(localized: "\(found) fichier trouvé") : String(localized: "\(found) fichiers trouvés")
    if missing == 0 { return first }
    return first + ", " + (missing == 1 ? String(localized: "\(missing) toujours introuvable") : String(localized: "\(missing) toujours introuvables"))
}
