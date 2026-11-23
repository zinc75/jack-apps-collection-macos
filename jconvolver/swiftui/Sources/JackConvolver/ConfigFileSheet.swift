// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import AppearanceKit
import JConvolverKit
import MatrixKit
import SwiftUI

/// The configuration file as it is: the numbers of the header, the names of the ports, and the text that is written. A page of the sidebar.
/// The impulse responses are edited on the page of the convolutions, not here.
struct ConfigFilePage: View {
    @Environment(AppModel.self) private var model
    @State private var tab = Tab.header

    enum Tab: Hashable { case header, ports, text }

    private var tabs: [Tab] { model.mode == .file ? [.header, .text] : [.header, .ports, .text] }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Fichier de configuration").font(.title2).fontWeight(.semibold)
                Text("Le contenu de \(model.name) tel que \(model.mode == .file ? "fconvolver" : "jconvolver") le lit. Les réponses impulsionnelles se règlent dans la page Convolutions.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Picker("Partie", selection: $tab) {
                ForEach(tabs, id: \.self) { t in
                    switch t {
                    case .header: Text("En-tête").tag(t)
                    case .ports: Text("Ports et connexions (\(model.document?.inputCount ?? 0) + \(model.document?.outputCount ?? 0))").tag(t)
                    case .text: Text("Fichier .conf complet").tag(t)
                    }
                }
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize().accentTint()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    LockBanner()
                    // The engine read the file once: while it runs, it is only looked at.
                    Group {
                        switch tab {
                        case .header: HeaderTab()
                        case .ports: PortsTab()
                        case .text: TextTab()
                        }
                    }
                    .disabled(model.isLocked)
                }
            }
            HStack {
                Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }.disabled(!model.canUndo).help("Annuler")
                Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }.disabled(!model.canRedo).help("Rétablir")
                Spacer()
                Button(model.savesAsNew ? "Enregistrer sous…" : "Enregistrer") { model.save() }.disabled(!model.isEdited && !model.savesAsNew)
            }
        }
        .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        #if DEBUG
        .onAppear {
            switch ProcessInfo.processInfo.environment["JACKCONVOLVER_CONFIGTAB"] { case "ports": tab = .ports; case "text": tab = .text; default: break }
        }
        #endif
    }
}

// MARK: Header

private struct HeaderTab: View {
    @Environment(AppModel.self) private var model
    @State private var manualRequested = false
    @State private var showsServer = false

    private var content: ConvDocument.Content? { model.document?.content }
    private var isManual: Bool {
        guard let c = content else { return false }
        return manualRequested || c.partition != nil || c.maxLength != nil || c.density != nil
    }
    private var period: Int { model.jack.bufferSize ?? 256 }
    private var rate: Double { Double(model.jack.sampleRate ?? 48000) }

    var body: some View {
        let automatic = model.automaticHeader
        VStack(alignment: .leading, spacing: 18) {
            if model.mode == .realTime {
                SettingsGroup("/jack/client") {
                    OptionRow("Nom du client", "Le nom sous lequel jconvolver se présente à JACK.", info: "L'option -N de la ligne de commande remplace ce nom.") {
                        CommitField(text: content?.client ?? "", placeholder: "jconvolver", width: 220) { value in
                            model.edit(String(localized: "nom du client JACK")) { $0.content.client = value.isEmpty ? nil : value }
                            return true
                        }
                    }
                }
            }
            SettingsGroup("/convolver/new") {
                OptionRow("Voies", "Le nombre d'entrées et de sorties de la matrice.") {
                    Text(verbatim: "\(model.document?.inputCount ?? 0) × \(model.document?.outputCount ?? 0)").foregroundStyle(.secondary).monospacedDigit()
                    Button("Modifier…") { model.showsResize = true }
                }
                OptionRow("Calcul automatique", "Les trois valeurs suivent les réponses impulsionnelles placées.",
                          info: model.mode == .file
                          ? "La partition, la longueur maximale et la densité sont calculées d'après les réponses impulsionnelles placées. Désactivé, elles se règlent à la main et sont écrites telles quelles dans le fichier."
                          : "La partition suit la période de JACK ; la longueur maximale et la densité sont calculées d'après les réponses impulsionnelles placées. Désactivé, elles se règlent à la main et sont écrites telles quelles dans le fichier.") {
                    Toggle("Calcul automatique", isOn: Binding(get: { !isManual }, set: { automaticOn in
                        if automaticOn {
                            manualRequested = false
                            model.edit(String(localized: "retour au calcul automatique")) { $0.content.partition = nil; $0.content.maxLength = nil; $0.content.density = nil }
                        } else {
                            // The manual values start from what was calculated.
                            manualRequested = true
                            model.edit(String(localized: "réglage à la main de l'en-tête")) {
                                $0.content.partition = automatic.partition
                                $0.content.maxLength = automatic.maxLength
                                $0.content.density = automatic.density
                            }
                        }
                    })).toggleStyle(.switch).labelsHidden().accentTint()
                }
                if isManual {
                    partitionRow(automatic)
                    OptionRow("Longueur maximale", "La plus longue réponse impulsionnelle telle que le moteur la lit, en échantillons. Calculée : \(automatic.maxLength).", info: "Retard compris, début ignoré retiré, fin tronquée par la longueur choisie. Ce n'est pas la longueur des fichiers. Au plus 1 048 576 échantillons.") {
                        CommitField(text: content?.maxLength.map(String.init) ?? "", placeholder: String(automatic.maxLength), width: 100, trailing: true) { value in
                            guard let v = Int(value) ?? (value.isEmpty ? 0 : nil), v >= 0 else { return false }
                            model.edit(String(localized: "longueur maximale")) { $0.content.maxLength = value.isEmpty ? nil : v }
                            return true
                        }
                    }
                    OptionRow("Densité", "La part des paires qui ont une réponse impulsionnelle, de 0 à 1. Calculée : \((automatic.density ?? 0).formatted(.number.precision(.fractionLength(2)))).", info: "Une paire est une entrée reliée à une sortie. Une densité proche de la réalité aide jconvolver à réserver la bonne quantité de mémoire.") {
                        CommitField(text: content?.density.map { $0.formatted(.number.precision(.fractionLength(0...2))) } ?? "",
                                    placeholder: (automatic.density ?? 0).formatted(.number.precision(.fractionLength(2))), width: 100, trailing: true) { value in
                            let v = Double(value.replacingOccurrences(of: ",", with: ".")) ?? (value.isEmpty ? 0 : nil)
                            guard let v, v >= 0, v <= 1 else { return false }
                            model.edit(String(localized: "densité")) { $0.content.density = value.isEmpty ? nil : v }
                            return true
                        }
                    }
                } else {
                    OptionRow("Partition", model.mode == .file ? "Sans effet sur le résultat." : "La période de JACK : aucune latence ajoutée.", info: model.mode == .file ? "fconvolver ne travaille pas en temps réel : la taille de partition ne change pas le fichier produit." : "La partition est la taille des blocs de calcul. En suivant la période de JACK, la convolution n'ajoute aucune latence.") {
                        Text(verbatim: String(automatic.partition)).foregroundStyle(.secondary).monospacedDigit()
                        Text("(calculé)").foregroundStyle(.secondary)
                    }
                    OptionRow("Longueur maximale", "La plus longue réponse impulsionnelle telle que le moteur la lit, en échantillons.", info: "Retard compris, début ignoré retiré, fin tronquée par la longueur choisie. Ce n'est pas la longueur des fichiers.") {
                        Text(verbatim: String(automatic.maxLength)).foregroundStyle(.secondary).monospacedDigit()
                        Text("(calculé)").foregroundStyle(.secondary)
                    }
                    OptionRow("Densité", "La part des paires qui ont une réponse impulsionnelle.", info: "Une paire est une entrée reliée à une sortie.") {
                        Text(verbatim: (automatic.density ?? 0).formatted(.number.precision(.fractionLength(2)))).foregroundStyle(.secondary).monospacedDigit()
                        Text("(calculé)").foregroundStyle(.secondary)
                    }
                }
            }
            if model.mode == .realTime {
                DisclosureGroup("Serveur JACK nommé (rarement utile)", isExpanded: Binding(get: { showsServer || content?.server != nil }, set: { showsServer = $0 })) {
                    SettingsGroup("/jack/server") {
                        OptionRow("Nom du serveur", "Seulement si JACK ne s'appelle pas « default ».", info: "L'option -s de la ligne de commande remplace ce nom.") {
                            CommitField(text: content?.server ?? "", placeholder: "default", width: 220) { value in
                                model.edit(String(localized: "nom du serveur JACK")) { $0.content.server = value.isEmpty ? nil : value }
                                return true
                            }
                        }
                    }
                }
            } else {
                Text("Sur fichier audio, JACK n'est pas utilisé : les noms du client et du serveur ne servent à rien.").font(.callout).foregroundStyle(.secondary)
            }
            FilteredProblems { kind in
                switch kind { case .partitionIllegal, .maxLengthOutOfRange, .maxLengthTooShort, .densityOutOfRange: true; default: false }
            }
        }
        .padding(.vertical, 4)
    }

    private func partitionRow(_ automatic: ConvHeader) -> some View {
        let current = content?.partition ?? automatic.partition
        var choices = [1, 2, 4, 8, 16].map { $0 * period }
        if !choices.contains(current) { choices.append(current) }
        func latency(_ p: Int) -> String { (Double(max(0, p - period)) / rate * 1000).formatted(.number.precision(.fractionLength(1))) }
        return OptionRow("Partition", "Plus elle est grande, moins le processeur travaille, mais plus la latence augmente.", info: "Une puissance de 2, de 64 à 8 192. Au-dessus de la période de JACK, la latence ajoutée est la différence, en échantillons, convertie en millisecondes.") {
            Picker("Partition", selection: Binding(get: { current }, set: { value in
                model.edit(String(localized: "partition")) { $0.content.partition = value }
            })) {
                ForEach(choices.sorted(), id: \.self) { p in
                    if p == period { Text(verbatim: "\(p) · \(String(localized: "période de JACK, aucune latence"))").tag(p) }
                    else if p < period { Text(verbatim: "\(p) · \(String(localized: "plus petite que la période de JACK, aucune latence"))").tag(p) }
                    else { Text(verbatim: "\(p) · \(String(localized: "latence ajoutée"))\u{00A0}+\(latency(p))\u{00A0}ms").tag(p) }
                }
            }
            .labelsHidden().fixedSize()
        }
    }
}

// MARK: Ports

private struct PortsTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let d = model.document {
                group("Entrées", "/input/name", d.content.inputs, isInput: true)
                group("Sorties", "/output/name", d.content.outputs, isInput: false)
            }
            Text("Un nom est unique, entrées et sorties confondues. Une voie n'est écrite dans le fichier que si elle est nommée ou connectée. Plusieurs ports de connexion se séparent par des espaces (entre guillemets si le nom en contient) : une autre version de jconvolver ne connecte que le premier.")
                .font(.callout).foregroundStyle(.secondary)
            FilteredProblems { kind in
                switch kind { case .emptyPortName, .duplicatePortName, .sharedPortName, .tooManyPorts: true; default: false }
            }
        }
        .padding(.vertical, 4)
    }

    private func group(_ title: LocalizedStringKey, _ command: String, _ ports: [ConvPortSpec], isInput: Bool) -> some View {
        SettingsGroup(title) {
            ForEach(Array(ports.enumerated()), id: \.offset) { i, port in
                HStack(spacing: 10) {
                    Text(verbatim: command).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).frame(width: 100, alignment: .leading)
                    Text(verbatim: "\(i + 1)").foregroundStyle(.secondary).monospacedDigit().frame(width: 28, alignment: .trailing)
                    CommitField(text: port.name ?? "", placeholder: "\(isInput ? "in" : "out")-\(i + 1)", width: 190) { value in
                        edit(i, isInput) { $0.name = value.isEmpty ? nil : value }
                        return true
                    }
                    CommitField(text: ConfWord.join(port.connections), placeholder: String(localized: "connecter à des ports JACK (facultatif)"), width: nil) { value in
                        // Several ports are separated by blanks; a name with blanks is between quotes.
                        guard let ports = ConfWord.split(value) else { return false }
                        edit(i, isInput) { $0.connections = ports }
                        return true
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 4)
            }
        }
    }

    private func edit(_ index: Int, _ isInput: Bool, _ change: @escaping (inout ConvPortSpec) -> Void) {
        model.edit(String(localized: "nom d'une voie")) { d in
            if isInput { change(&d.content.inputs[index]) } else { change(&d.content.outputs[index]) }
        }
    }
}

// MARK: Text

private struct TextTab: View {
    @Environment(AppModel.self) private var model
    @State private var copied = false

    var body: some View {
        let text = model.configText
        let lines = text.components(separatedBy: "\n")
        let cap = 1500
        VStack(alignment: .leading, spacing: 10) {
            Text("Le texte qui sera écrit dans le fichier à l'enregistrement. Un fichier qui n'a pas été modifié est écrit tel qu'il a été lu.")
                .font(.callout).foregroundStyle(.secondary)
            // The text is shown as in a terminal, dark in both appearances.
            Text(ConfHighlighter.attributed(lines.prefix(cap).joined(separator: "\n")))
                .font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.12), lineWidth: 0.5))
            if lines.count > cap {
                Text("… et \(lines.count - cap) lignes de plus, toutes de la même forme.").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button(copied ? "Copié" : "Copier") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    copied = true
                }
                Spacer()
            }
        }
        .padding(.vertical, 4)
    }
}

/// Colours of the text of a configuration: the commands, the words between quotes, and the comments.
enum ConfHighlighter {
    static func attributed(_ text: String) -> AttributedString {
        var out = AttributedString()
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        for (n, line) in lines.enumerated() {
            if n > 0 { out += AttributedString("\n") }
            let line = String(line)
            if line.hasPrefix("#") {
                var a = AttributedString(line); a.foregroundColor = Color(red: 0.56, green: 0.56, blue: 0.58); out += a; continue
            }
            var rest = Substring(line), first = true
            while !rest.isEmpty {
                if rest.first == " " {
                    let spaces = rest.prefix(while: { $0 == " " }); out += AttributedString(String(spaces)); rest = rest.dropFirst(spaces.count); continue
                }
                var word: Substring
                if rest.first == "\"", let end = rest.dropFirst().firstIndex(of: "\"") { word = rest[rest.startIndex...end] }
                else { word = rest.prefix(while: { $0 != " " }) }
                var a = AttributedString(String(word))
                if first, word.hasPrefix("/") { a.foregroundColor = Color(red: 0.54, green: 0.58, blue: 1.0) }
                else if word.hasPrefix("\"") || word.contains("/") || word.contains(".") && Double(word) == nil { a.foregroundColor = Color(red: 0.31, green: 0.83, blue: 0.50) }
                else { a.foregroundColor = Color(white: 0.9) }
                out += a
                rest = rest.dropFirst(word.count)
                first = false
            }
        }
        return out
    }
}

/// The problems of one kind, in the part of the window they are about.
private struct FilteredProblems: View {
    @Environment(AppModel.self) private var model
    let keep: (ConvProblem.Kind) -> Bool

    var body: some View {
        let list = model.problems.filter { keep($0.kind) }
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(list.enumerated()), id: \.offset) { _, problem in
                    Label(problem.message, systemImage: problem.severity == .error ? "exclamationmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(problem.severity == .error ? Color.red : Color.orange).font(.callout)
                }
            }
        }
    }
}

/// A field whose text is kept apart while it is edited: what is typed is applied when it is validated (return, or leaving the field);
/// when the value is refused the field comes back to what it was.
struct CommitField: View {
    let text: String
    var placeholder: String = ""
    var width: CGFloat? = 140
    var trailing = false
    let commit: (String) -> Bool
    @State private var edited = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $edited, prompt: Text(verbatim: placeholder))
            .labelsHidden().textFieldStyle(.roundedBorder).multilineTextAlignment(trailing ? .trailing : .leading)
            .frame(width: width).frame(maxWidth: width == nil ? .infinity : nil).focused($focused)
            .onAppear { edited = text }
            .onChange(of: text) { _, new in edited = new }
            .onSubmit { validate() }
            .onChange(of: focused) { _, now in if !now { validate() } }
    }

    private func validate() {
        let value = edited.trimmingCharacters(in: .whitespaces)
        if value != text, !commit(value) { edited = text }
    }
}
