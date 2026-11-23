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
        @Bindable var model = model
        SettingsPage {
            VStack(alignment: .leading, spacing: 4) {
                Text("Jack Convolver").font(.largeTitle).fontWeight(.semibold)
                Text("Convoluez vos signaux avec des réponses impulsionnelles : en direct dans JACK, ou sur un fichier audio.")
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Mode").font(.headline)
                HStack(alignment: .top, spacing: 14) {
                    ModeTile(mode: .realTime, symbol: "dot.radiowaves.left.and.right", title: "Temps réel",
                             text: "Le moteur tourne dans JACK jusqu'à ce que vous l'arrêtiez : ses entrées et ses sorties sont des ports JACK.",
                             program: "jconvolver")
                    ModeTile(mode: .file, symbol: "waveform.path", title: "Sur fichier audio",
                             text: "Sans JACK : un fichier audio entre, un fichier convolué sort, en quelques secondes.",
                             program: "fconvolver")
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Configuration").font(.headline)
                HStack(spacing: 12) {
                    Button { model.openPanel() } label: { Label("Ouvrir une configuration…", systemImage: "folder") }
                        .buttonStyle(.borderedProminent).accentTint().controlSize(.large)
                    Button { model.showsNewConfiguration = true } label: { Label("Nouvelle configuration…", systemImage: "plus") }
                        .controlSize(.large)
                }
            }
            if !model.recents.isEmpty {
                SettingsGroup("Récentes") {
                    ForEach(model.recents, id: \.self) { url in
                        HStack(spacing: 4) {
                            Button { model.open(url) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(url.lastPathComponent).fontWeight(.medium)
                                    Text(url.deletingLastPathComponent().path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
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

/// One of the two ways to run: a tile to choose, with what it does.
struct ModeTile: View {
    @Environment(AppModel.self) private var model
    @Environment(\.appAccentColor) private var accent
    let mode: RunMode
    let symbol: String
    let title: LocalizedStringKey
    let text: LocalizedStringKey
    let program: String
    @State private var hovered = false

    private var selected: Bool { model.mode == mode }
    private var locked: Bool { model.controller.isRunning && !selected }

    var body: some View {
        Button { model.mode = mode } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(selected ? AnyShapeStyle(accent) : AnyShapeStyle(Color.primary.opacity(0.1)))
                            .frame(width: 38, height: 38)
                        Image(systemName: symbol).font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.7))
                    }
                    // The program that runs, beside the picture.
                    Text(verbatim: program).font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary).padding(.leading, 4)
                    Spacer()
                    if selected { Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(accent) }
                }
                Text(title).font(.title3).fontWeight(.semibold)
                Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 170, maxHeight: 170, alignment: .topLeading)
            .background(Color.primary.opacity(selected ? 0.08 : (hovered ? 0.06 : 0.035)), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(selected ? AnyShapeStyle(accent) : AnyShapeStyle(Color.primary.opacity(0.14)), lineWidth: selected ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .disabled(locked)
        .opacity(locked ? 0.5 : 1)
        .help(locked ? "Arrêtez le moteur pour changer de mode." : "")
        .accessibilityAddTraits(selected ? .isSelected : [])
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
            Text("Passées à jconvolver au démarrage. Elles sont mémorisées avec cette configuration, pas dans le fichier de configuration.")
                .foregroundStyle(.secondary)
            LockBanner()
            SettingsGroup("Calcul") {
                OptionRow("Mode vectoriel", "Calcul vectoriel de quatre fréquences à la fois.", info: "Traite quatre fréquences à la fois avec des instructions vectorielles.") {
                    Toggle("-V", isOn: $model.options.vectorMode).toggleStyle(.switch).labelsHidden().accentTint()
                }
                OptionRow("Optimiser les transformées", "FFTW cherche l'algorithme le plus rapide.", info: "FFTW teste plusieurs algorithmes au démarrage, ce qui ajoute environ 15 ms.") {
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
                    OptionRow("Compenser une latence", "Avance chaque réponse impulsionnelle de ce nombre d'échantillons.", info: "Pour compenser un retard introduit ailleurs dans la chaîne. Une réponse impulsionnelle qui n'a pas assez de retard est raccourcie au début, ou supprimée si c'est une impulsion ou un filtre de Hilbert.") {
                        NumberField(label: "Latence à compenser", value: $model.options.latencyCompensation, range: 0...1_000_000)
                        Text("échantillons").font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                SettingsGroup("Sortie") {
                    OptionRow("Couper à la longueur de l'entrée", "La sortie dure autant que l'entrée.", info: "Sans cette option, la sortie garde la queue de la réverbération et dure plus longtemps que l'entrée.") {
                        Toggle("-T", isOn: $model.options.truncate).toggleStyle(.switch).labelsHidden().accentTint()
                    }
                }
            }
            Button("Rétablir les valeurs par défaut") { model.options = EngineCommand.Options(); model.refreshProblems() }
                .disabled(running)
        }
        .disabled(running)
        .onChange(of: model.options.latencyCompensation) { _, _ in model.refreshProblems() }
    }
}

/// The two files of the processing on sound files.
struct AudioFilesGroup: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        SettingsGroup("Fichiers audio") {
            OptionRow("Fichier d'entrée", "Le fichier que fconvolver lit.", info: "Il doit avoir autant de voies que la matrice a d'entrées.") {
                Text(model.inputFile?.lastPathComponent ?? "—").foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Button("Choisir…") { chooseInput() }
            }
            OptionRow("Fichier de sortie", "Le fichier que fconvolver écrit.", info: "Écrit en WAV à virgule flottante, avec autant de voies que la matrice a de sorties.") {
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
                OptionRow("Carte d'aperçu au survol", "Une petite carte montre le contenu de la case sous le pointeur.", info: "Fichier et voie, gain, retard, début et longueur. Elle disparaît pendant une sélection ou quand ⌘ ou ⇧ est enfoncé.") {
                    Toggle("Carte d'aperçu au survol", isOn: $model.showsHoverCard).toggleStyle(.switch).labelsHidden().accentTint()
                }
            }
        }
    }
}
