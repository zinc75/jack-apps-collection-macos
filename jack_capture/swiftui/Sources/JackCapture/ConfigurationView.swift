// SPDX-License-Identifier: GPL-2.0-or-later

import SwiftUI
import AppearanceKit
import MatrixKit
import JackCaptureKit

/// A row of a settings group: title, an explanation under it, and the control on the right.
/// Same shape as the rows of System Settings.
extension EnvironmentValues {
    /// The title of the row a field sits in, read aloud by VoiceOver.
    @Entry var fieldLabel: LocalizedStringKey = ""
}

struct OptionRow<Control: View>: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    /// A message that replaces the subtitle, with a warning sign, and makes a warning-coloured outline pulse around the row.
    var warning: String?
    /// False when the warning is shown but the pulsing is carried by a control of the row.
    var pulsesRow = true
    @ViewBuilder var control: Control

    init(_ title: LocalizedStringKey, _ subtitle: LocalizedStringKey? = nil, warning: String? = nil, pulsesRow: Bool = true,
         @ViewBuilder control: () -> Control) {
        self.title = title
        self.subtitle = subtitle
        self.warning = warning
        self.pulsesRow = pulsesRow
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let warning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).fontWeight(.medium).foregroundStyle(Color.alert)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                } else if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) { control }
                .environment(\.fieldLabel, title)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay { if warning != nil && pulsesRow { PulsingOutline(color: .alert).padding(3) } }
    }
}

/// A rounded outline whose opacity breathes slowly, to draw the eye.
struct PulsingOutline: View {
    let color: Color
    var radius: CGFloat = 9
    @State private var bright = false

    var body: some View {
        RoundedRectangle(cornerRadius: radius)
            .strokeBorder(color, lineWidth: 1.5)
            .opacity(bright ? 1 : 0.2)
            .allowsHitTesting(false)
            .onAppear { withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { bright = true } }
    }
}

/// A titled block of rows on an opaque fill, with hairlines between the rows.
struct SettingsGroup<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var content: Content

    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline).foregroundStyle(.secondary).padding(.leading, 12)
            VStack(spacing: 0) {
                Group(subviews: content) { rows in
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        if index > 0 { Divider().padding(.leading, 14) }
                        row
                    }
                }
            }
            .blockBackground()
        }
    }
}

/// A number field. A unit, if any, sits inside the box after the digits: a suffix that cannot be edited.
struct NumberField: View {
    @Environment(\.fieldLabel) private var label
    @Binding var value: Int
    var range: ClosedRange<Int>?
    var unit: LocalizedStringKey?
    /// Width of the digits area, in points; the unit comes after it at its own width.
    var width: CGFloat = 56
    /// What is typed: kept as text, so that the field can be emptied on the way to another number.
    @State private var text = ""
    @FocusState private var isEditing: Bool

    var body: some View {
        HStack(spacing: 4) {
            TextField(label, text: $text)
                .labelsHidden()
                .textFieldStyle(.plain)
                .frame(width: width)
                .multilineTextAlignment(unit == nil ? .center : .trailing)
                .focused($isEditing)
                .onSubmit { commit() }
                .onChange(of: text) { if IntegerInput.digits(text) != text { text = IntegerInput.digits(text) } }
                .onChange(of: isEditing) { if !isEditing { commit() } }
                .onChange(of: value) { if !isEditing { text = String(value) } }
                .onAppear { text = String(value) }
            if let unit {
                Text(unit).foregroundStyle(.secondary).fixedSize()
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
        .fieldOutline()
    }

    /// The number typed goes into the value, inside its range; the field then shows what the value became.
    private func commit() {
        value = IntegerInput.commit(text, current: value, range: range)
        text = String(value)
    }
}

/// A duration as minutes and seconds side by side: 4 min 25 s. The seconds stop at 59.
struct DurationField: View {
    @Binding var seconds: Int

    var body: some View {
        HStack(spacing: 8) {
            NumberField(value: minutes, range: 0...(TimeSpan.range.upperBound / 60), unit: "min", width: 40)
                .environment(\.fieldLabel, "Minutes")
            NumberField(value: remainder, range: 0...59, unit: "s", width: 40)
                .environment(\.fieldLabel, "Secondes")
        }
    }

    private var minutes: Binding<Int> {
        Binding(get: { seconds / 60 }, set: { seconds = TimeSpan.seconds(minutes: $0, seconds: seconds % 60) })
    }

    private var remainder: Binding<Int> {
        Binding(get: { seconds % 60 }, set: { seconds = TimeSpan.seconds(minutes: seconds / 60, seconds: $0) })
    }
}

/// A pop-up menu of fixed width, so that all the menus of the window line up whatever they hold.
struct MenuField<Value: Hashable>: View {
    @Environment(\.fieldLabel) private var label
    @Binding var selection: Value
    let options: [Value]
    let title: (Value) -> Text

    var body: some View {
        Menu {
            Picker("", selection: $selection) {
                ForEach(options, id: \.self) { title($0).tag($0) }
            }
            .pickerStyle(.inline).labelsHidden()
        } label: {
            HStack {
                title(selection)
                Spacer(minLength: 8)
                Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(width: 230, height: 26)
            .background(.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
            .fieldOutline()
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// A settings group that folds away: a header with a chevron, rows below when open.
struct CollapsibleSettingsGroup<Content: View>: View {
    let title: LocalizedStringKey
    @Binding var isExpanded: Bool
    @ViewBuilder var content: Content

    init(_ title: LocalizedStringKey, isExpanded: Binding<Bool>, @ViewBuilder content: () -> Content) {
        self.title = title
        self._isExpanded = isExpanded
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right").font(.caption.weight(.bold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    Text(title).font(.headline)
                }
                .foregroundStyle(.secondary)
                .padding(.leading, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            if isExpanded {
                VStack(spacing: 0) {
                    Group(subviews: content) { rows in
                        ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                            if index > 0 { Divider().padding(.leading, 14) }
                            row
                        }
                    }
                }
                .blockBackground()
                .transition(.opacity)
            }
        }
    }
}

/// Configuration of the recording: edits `model.settings`.
struct ConfigurationView: View {
    /// The section of the settings shown: each one is a page of its own.
    let section: MainView
    @Environment(RecorderModel.self) private var model
    @Environment(AppearanceSettings.self) private var appearance
    @State private var limitNote: String?
    @State private var noteTask: Task<Void, Never>?
    @State private var nextName = ""

    var body: some View {
        @Bindable var model = model
        if section == .channels {
            channelsPage
        } else {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
            if model.phase.isLocked { lockedBanner }
            Group {

                if section == .file {
SettingsGroup("Fichier") {
                    OptionRow("Dossier", "Où le fichier est enregistré.") {
                        Button(action: chooseFolder) {
                            Label((model.settings.folder as NSString).abbreviatingWithTildeInPath, systemImage: "folder")
                        }
                        .buttonStyle(.bordered).fieldOutline()
                    }
                    OptionRow("Nom", model.settings.numbering
                              ? "Prochain nom libre dans le dossier : \(nextName)."
                              : "Nom du fichier : \(nextName).") {
                        TextField("", text: $model.settings.name)
                            .textFieldStyle(.roundedBorder).multilineTextAlignment(.leading).frame(width: 180).fieldOutline()
                    }
                    OptionRow("Numéroter automatiquement",
                              "Ajoute un numéro pour ne jamais écraser un enregistrement existant.") {
                        Toggle("", isOn: $model.settings.numbering).labelsHidden().toggleStyle(.switch).accentTint()
                    }
                    OptionRow("Format", model.settings.format.summary) {
                        MenuField(selection: formatBinding, options: CaptureFormat.allCases) { Text(verbatim: $0.displayName) }
                    }
                    if !model.settings.format.isLossy {
                        OptionRow("Profondeur", "La précision de chaque échantillon.") {
                            MenuField(selection: $model.settings.depth, options: model.settings.format.depths) { Text($0.label) }
                        }
                    } else if model.settings.format == .mp3 {
                        OptionRow("Débit", "Plus il est élevé, plus le fichier est fidèle et volumineux.") {
                            MenuField(selection: $model.settings.mp3Bitrate, options: [96, 128, 160, 192, 256, 320]) { Text("\($0) kbit/s") }
                        }
                    } else if model.settings.format == .ogg {
                        OptionRow("Qualité", "De 0 (petit fichier) à 100 (haute qualité).") {
                            Slider(value: oggQualityBinding, in: 0...100, step: 5).accentTint().frame(width: 140)
                            Text("\(model.settings.oggQuality)").monospacedDigit().frame(width: 28, alignment: .trailing)
                        }
                    }
                }
}
                if section == .startStop {
SettingsGroup("Démarrage et arrêt") {
                    OptionRow("Démarrer", "Dès que le bouton rouge est pressé.") {
                        MenuField(selection: $model.settings.startMode, options: StartMode.allCases) { Text($0.label) }
                    }
                    OptionRow("Arrêt programmé", "Arrête et ferme le fichier après une durée donnée.") {
                        Toggle("", isOn: $model.settings.scheduledStop).labelsHidden().toggleStyle(.switch).accentTint()
                    }
                    if model.settings.scheduledStop {
                        OptionRow("Durée", "Durée de l'enregistrement, en minutes et secondes.") {
                            DurationField(seconds: $model.settings.durationSeconds)
                        }
                    }
                    OptionRow("Préenregistrement (timemachine)",
                              "L'écoute tourne en permanence, sans fichier. Au lancement de l'enregistrement, le fichier commence par les dernières secondes déjà écoulées, pour ne pas rater le début.") {
                        Toggle("", isOn: $model.settings.timemachine).labelsHidden().toggleStyle(.switch).accentTint()
                    }
                    if model.settings.timemachine {
                        OptionRow("Secondes conservées", "Durée déjà écoulée que le fichier reprend au début.") {
                            NumberField(value: $model.settings.timemachineSeconds, range: 1...60, unit: "s")
                        }
                    }
                }
}
                if section == .advanced {
SettingsGroup("Avancé") {
                    OptionRow("Fichier de temps",
                              "Écrit à côté de l'enregistrement un petit fichier texte avec l'heure exacte du premier échantillon, pour caler plusieurs enregistrements.") {
                        Toggle("", isOn: $model.settings.writesTimeFile).labelsHidden().toggleStyle(.switch).accentTint()
                    }
                    OptionRow("Découper en plusieurs fichiers",
                              "Ferme le fichier et en ouvre un nouveau à intervalles réguliers, sans perdre un échantillon.") {
                        Toggle("", isOn: $model.settings.rotatesFiles).labelsHidden().toggleStyle(.switch).accentTint()
                    }
                    if model.settings.rotatesFiles {
                        OptionRow("Durée de chaque fichier", "En minutes et secondes.") {
                            DurationField(seconds: $model.settings.rotationSeconds)
                        }
                    }
                    OptionRow("Tampon mémoire",
                              "Taille du tampon entre JACK et le disque, en secondes. À augmenter si le disque est lent.") {
                        NumberField(value: $model.settings.bufferSeconds, range: 1...60, unit: "s")
                    }
                    OptionRow("Contrôle par OSC",
                              "Permet de piloter l'enregistrement depuis un autre logiciel, par messages OSC.") {
                        Toggle("", isOn: $model.settings.oscEnabled).labelsHidden().toggleStyle(.switch).accentTint()
                    }
                    if model.settings.oscEnabled {
                        OptionRow("Port OSC", "Port UDP sur lequel jack_capture écoute.") {
                            NumberField(value: $model.settings.oscPort, range: 1024...65535, width: 72)
                        }
                    }
                    OptionRow("Nom du client JACK",
                              "Nom sous lequel l'enregistreur apparaît dans JACK. À changer pour en lancer deux à la fois.") {
                        BadgeView(client: model.settings.jackClientName, size: 24)   // colour and letters follow the name
                        TextField("", text: $model.settings.clientName, prompt: Text(verbatim: CaptureSettings.defaultClientName))
                            .textFieldStyle(.roundedBorder).multilineTextAlignment(.leading).frame(width: 180).fieldOutline()
                    }
                }
}
            }
            .disabled(model.phase.isLocked)
            if section == .display {
SettingsGroup("Affichage") {
                OptionRow("Apparence", "Sombre par défaut ; Système suit le réglage de macOS.") {
                    AppearanceModePicker(settings: appearance)
                }
                OptionRow("Couleur d'accent") {
                    AccentSwatches(settings: appearance)
                }
                OptionRow("Vumètres",
                          "Mesure le niveau de chaque voie et l'affiche pendant l'enregistrement. À désactiver si la machine est chargée, surtout avec beaucoup de voies. Sans effet sur le fichier.") {
                    Toggle("", isOn: $model.settings.metersEnabled).labelsHidden().toggleStyle(.switch).accentTint()
                }
                OptionRow("Vumètres avant l'enregistrement",
                          "Prévisualise les niveaux des sources choisies tant que la page Enregistrement attend, par un client JACK de mesure (« Jack Capture levels ») relié à ces sources. Il disparaît du graphe dès qu'un enregistrement commence.") {
                    Toggle("", isOn: $model.settings.monitorsLevels).labelsHidden().toggleStyle(.switch).accentTint()
                }
            }
}
            }
            .padding(24)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .softScrollEdges()
        #if DEBUG
        .defaultScrollAnchor(ProcessInfo.processInfo.environment["JACKCAPTURE_ADV"] != nil ? .bottom : nil)
        #endif
        // No text field takes the keyboard focus when the window opens.
        .onAppear { DispatchQueue.main.async { NSApp.keyWindow?.makeFirstResponder(nil) } }
        .task(id: model.settings) { nextName = model.nextFileName() }
        #if DEBUG
        .task {
            if let name = ProcessInfo.processInfo.environment["JACKCAPTURE_CLIENT"] { model.settings.clientName = name }
            if ProcessInfo.processInfo.environment["JACKCAPTURE_NOTE"] != nil {
                model.settings.setChannels(12)
                formatBinding.wrappedValue = .flac
            }
        }
        #endif
        }
    }

    private var lockedBanner: some View {
        HStack {
            Label("Configuration verrouillée : l'enregistrement est en cours", systemImage: "lock.fill")
                .foregroundStyle(.orange)
            Spacer()
            Button("Voir l'enregistrement") { model.view = .recording }.buttonStyle(.link)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(.orange.opacity(0.16), in: RoundedRectangle(cornerRadius: 12))
    }

    /// The channels page: the number of channels, then the matrix of sources over the rest of the height.
    private var channelsPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                if model.phase.isLocked { lockedBanner }
                SettingsGroup("Voies") {
                    OptionRow("Voies à enregistrer", channelsSubtitle, warning: limitNote, pulsesRow: limitNote != nil) {
                        NumberField(value: channelsBinding, unit: "voies")
                    }
                }
                .disabled(model.phase.isLocked)
            }
            .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 12)
            SourcesMatrix()
        }
        // The texts of this page wrap: measured with no width at all they would be as tall as the window, and
        // the whole window would be pushed up. The page says how narrow it can get.
        .frame(minWidth: 560)
    }

    private var channelsSubtitle: LocalizedStringKey {
        let sources = SourceAssignment(model.settings.sources, channels: model.settings.channels)
        if sources.usedCount == 0 { return "Aucune source choisie : rien ne sera relié, les voies seront muettes." }
        return "Sources choisies : \(sources.usedCount) sur \(sources.channelCount)."
    }

    private var channelsBinding: Binding<Int> {
        Binding(get: { model.settings.channels }, set: { setChannels($0) })
    }

    private var formatBinding: Binding<CaptureFormat> {
        Binding(get: { model.settings.format }, set: { format in
            let change = model.settings.setFormat(format)
            if change.channelsReduced {
                showNote(String(localized: "Ce format accepte \(format.maxChannels) voies au maximum.")
                         + " " + String(localized: "Le nombre de voies a été réduit."))
            }
        })
    }

    private var oggQualityBinding: Binding<Double> {
        Binding(get: { Double(model.settings.oggQuality) }, set: { model.settings.oggQuality = Int($0) })
    }

    private func setChannels(_ n: Int) {
        let max = model.settings.format.maxChannels
        if n > max { showNote(String(localized: "Ce format accepte \(max) voies au maximum.")) }
        model.settings.setChannels(n)
    }

    private func showNote(_ text: String) {
        withAnimation(.easeInOut(duration: 0.25)) { limitNote = text }
        noteTask?.cancel()
        noteTask = Task {
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled { withAnimation(.easeInOut(duration: 0.4)) { limitNote = nil } }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = model.settings.folderURL
        panel.prompt = String(localized: "Choisir")
        if panel.runModal() == .OK, let url = panel.url {
            model.settings.folder = (url.path as NSString).abbreviatingWithTildeInPath
        }
    }
}
