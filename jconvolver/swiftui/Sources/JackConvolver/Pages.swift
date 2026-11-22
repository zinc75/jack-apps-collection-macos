// SPDX-License-Identifier: GPL-3.0-or-later

import AppearanceKit
import JConvolverKit
import MatrixKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: Home

struct HomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        SettingsPage {
            VStack(alignment: .leading, spacing: 4) {
                Text("Jack Convolver").font(.largeTitle).fontWeight(.semibold)
                Text("Une matrice de convolutions : des entrées, des sorties, et une réponse impulsionnelle (RI) pour chaque paire qui en a besoin.")
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Button { model.openPanel() } label: { Label("Ouvrir une configuration…", systemImage: "folder") }
                    .buttonStyle(.borderedProminent).accentTint().controlSize(.large)
                Button { model.showsNewConfiguration = true } label: { Label("Nouvelle configuration…", systemImage: "plus") }
                    .controlSize(.large)
            }
            if !model.recents.isEmpty {
                SettingsGroup("Récentes") {
                    ForEach(model.recents, id: \.self) { url in
                        HStack(spacing: 4) {
                            Button { model.open(url) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(url.lastPathComponent).fontWeight(.medium)
                                    Text(url.deletingLastPathComponent().path).font(.caption).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, 14).padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            // Off the list only: the file stays where it is.
                            Button { model.forgetRecent(url) } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless).foregroundStyle(.secondary).padding(.trailing, 12)
                                .help("Retirer de la liste (le fichier n'est pas supprimé)")
                        }
                    }
                }
                Button("Vider la liste") { model.clearRecents() }
                    .buttonStyle(.link).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: Ports (the page that comes next)

struct PortsView: View {
    var body: some View {
        SettingsPage {
            Text("Connexions JACK").font(.title2).fontWeight(.semibold)
            Text("Les connexions des entrées et des sorties aux ports des autres applications arrivent dans les prochaines versions de cette interface.")
                .foregroundStyle(.secondary)
        }
    }
}

/// What is to settle, one line each, the worst first.
struct ProblemList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        SettingsGroup("À régler") {
            ForEach(Array(model.problems.enumerated()), id: \.offset) { _, problem in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: problem.severity == .error ? "exclamationmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(problem.severity == .error ? Color.red : Color.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(problem.place).font(.caption).foregroundStyle(.secondary)
                        Text(problem.message).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
            }
        }
    }
}

// MARK: Launch options

struct LaunchView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let running = model.controller.isRunning
        SettingsPage {
            Text("Options de lancement").font(.title2).fontWeight(.semibold)
            Text(model.mode == .file ? "Passées à fconvolver au démarrage. Elles sont mémorisées avec cette configuration, pas dans le fichier de configuration."
                                     : "Passées à jconvolver au démarrage. Elles sont mémorisées avec cette configuration, pas dans le fichier de configuration.")
                .foregroundStyle(.secondary)
            if model.mode == .file { AudioFilesGroup() }
            SettingsGroup("Calcul") {
                OptionRow("Mode vectoriel", "Traite quatre fréquences à la fois avec des instructions vectorielles.") {
                    Toggle("-V", isOn: $model.options.vectorMode).toggleStyle(.switch).labelsHidden().accentTint()
                }
                OptionRow("Optimiser les transformées", "FFTW teste plusieurs algorithmes au démarrage, ce qui ajoute environ 15 ms.") {
                    Toggle("-M", isOn: $model.options.measure).toggleStyle(.switch).labelsHidden().accentTint()
                }
                if model.mode == .realTime {
                    OptionRow("Protection contre les dénormaux", "Ajoute aux entrées un bruit inaudible de −306 dB.") {
                        Toggle("-Z", isOn: $model.options.denormalProtection).toggleStyle(.switch).labelsHidden().accentTint()
                    }
                }
            }
            if model.mode == .realTime {
                SettingsGroup("Latence") {
                    OptionRow("Compenser une latence", "Avance chaque RI de ce nombre d'échantillons, pour compenser un retard introduit ailleurs dans la chaîne. Une RI qui n'a pas assez de retard est raccourcie au début, ou supprimée si c'est une impulsion ou un filtre de Hilbert.") {
                        NumberField(label: "Latence à compenser", value: $model.options.latencyCompensation, range: 0...1_000_000)
                        Text("échantillons").font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                SettingsGroup("Sortie") {
                    OptionRow("Couper à la longueur de l'entrée", "Sans cette option, la sortie garde la queue de la réverbération et dure plus longtemps que l'entrée.") {
                        Toggle("-T", isOn: $model.options.truncate).toggleStyle(.switch).labelsHidden().accentTint()
                    }
                }
            }
            Button("Rétablir les valeurs par défaut") { model.options = EngineCommand.Options(); model.refreshProblems() }
                .disabled(running)
        }
        .onChange(of: model.options.latencyCompensation) { _, _ in model.refreshProblems() }
    }
}

/// The two files of the processing on sound files.
struct AudioFilesGroup: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        SettingsGroup("Fichiers audio") {
            OptionRow("Fichier d'entrée", "fconvolver lit ce fichier : il doit avoir autant de voies que la matrice a d'entrées.") {
                Text(model.inputFile?.lastPathComponent ?? "—").foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Button("Choisir…") { chooseInput() }
            }
            OptionRow("Fichier de sortie", "Écrit en WAV à virgule flottante, avec autant de voies que la matrice a de sorties.") {
                Text(model.outputFile?.lastPathComponent ?? "—").foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Button("Choisir…") { chooseOutput() }
            }
        }
    }

    private func chooseInput() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK { model.inputFile = panel.url }
    }

    private func chooseOutput() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.wav]
        panel.nameFieldStringValue = "sortie.wav"
        if panel.runModal() == .OK { model.outputFile = panel.url }
    }
}

// MARK: Display

struct DisplayView: View {
    @Environment(AppearanceSettings.self) private var appearance
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        SettingsPage {
            Text("Affichage").font(.title2).fontWeight(.semibold)
            SettingsGroup("Apparence") {
                OptionRow("Apparence") { AppearanceModePicker(settings: appearance) }
                OptionRow("Couleur d'accent") { AccentSwatches(settings: appearance) }
            }
            SettingsGroup("Matrice") {
                OptionRow("Carte d'aperçu au survol", "Quand le pointeur est sur une case, une petite carte montre ce qu'elle contient : fichier et voie, gain, retard, début et longueur.") {
                    Toggle("Carte d'aperçu au survol", isOn: $model.showsHoverCard).toggleStyle(.switch).labelsHidden().accentTint()
                }
            }
        }
    }
}
