// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import AppearanceKit
import JConvolverKit
import PlotKit
import SwiftUI

/// The page "Troncature" of the inspector of the page of an impulse response: where the engine starts reading the file and where it stops, in frames, to type
/// or to set from what the analysis found. It is the `offset` and the `length` of the impulse response in the .conf file, not a setting of the
/// plot. The handles on the curve change the same two values.
struct ZoneInspector: View {
    @Environment(\.appAccentColor) private var accent
    @Environment(AppModel.self) private var model
    /// The zone in frames, from the first frame read to the last one (the end of the file when the engine reads to the end).
    let zone: ClosedRange<Double>
    /// The frames of the file.
    let total: Int
    let sampleRate: Double
    let attack: Int?
    let tail: Int?
    /// Applies a new start and end, in frames.
    let apply: (_ start: Int, _ end: Int) -> Void

    @State private var startText = ""
    @State private var endText = ""
    @FocusState private var focus: Field?
    private enum Field { case start, end }

    private var start: Int { Int(zone.lowerBound.rounded()) }
    private var end: Int { Int(zone.upperBound.rounded()) }
    private var last: Int { max(total - 1, 1) }

    private func milliseconds(_ frames: Int) -> String {
        guard sampleRate > 0 else { return "" }
        return (Double(frames) / sampleRate * 1000).formatted(.number.precision(.fractionLength(1))) + " ms"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // What follows is written in the .conf file and changes what the engine does: it is not a setting of the plot.
            Text("Paramètres du moteur de convolution")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12).padding(.bottom, 2)
            PlotInspectorSection(id: "zoneLimits", title: String(localized: "Début et fin retenus"),
                                 info: String(localized: "Tronque la réponse impulsionnelle : le moteur ne lit que cette partie du fichier. Ces valeurs sont écrites dans le fichier .conf (offset et length). Tire les poignées sur la courbe, ou tape les valeurs.")) {
                // Three columns that line up: the label, the value in a field of the same width for every row, and the time it makes.
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                    GridRow {
                        label(String(localized: "Début"))
                        field($startText, .start) { commit(startText, isStart: true) }
                        time(start)
                    }
                    GridRow {
                        label(String(localized: "Fin"))
                        field($endText, .end) { commit(endText, isStart: false) }
                        time(end)
                    }
                    GridRow {
                        label(String(localized: "Longueur"))
                        // Under the text of the fields, not under their frame.
                        Text(verbatim: "\(max(end - start, 0))").monospacedDigit()
                            .frame(width: Self.fieldWidth, alignment: .trailing).padding(.trailing, 8)
                        time(max(end - start, 0))
                    }
                }
                .font(.callout)
            }
            PlotInspectorSection(id: "zoneMarks", title: String(localized: "Repères"),
                                 info: String(localized: "Repères trouvés dans le fichier, dans le domaine temporel : le début de l'attaque est à −60 dB sous la crête, la fin utile à −90 dB.")) {
                VStack(alignment: .leading, spacing: 8) {
                    AccentLinkButton("Début à l'attaque") { if let attack { apply(attack, end) } }
                        .disabled(attack == nil || attack == start)
                    AccentLinkButton("Fin à la fin utile") { if let tail { apply(start, tail) } }
                        .disabled(tail == nil || min(tail ?? 0, last) == end)
                    AccentLinkButton("Tout le fichier") { apply(0, last) }
                        .disabled(start == 0 && end >= last)
                }
                .font(.callout)
            }
            fadeSection
        }
        .onAppear { syncTexts() }
        .onChange(of: zone) { _, _ in syncTexts(); clampFade() }
    }

    // MARK: The fade

    /// The fade is not a setting of the engine: it is set here as a draft, shown on the plots, and applying it writes a new audio file.
    private var fadeSection: some View {
        let length = model.fadeContext()?.length ?? 0
        return PlotInspectorSection(id: "zoneFade", title: String(localized: "Fondu"),
                             info: String(localized: "Un fondu à la montée et à la descente de la partie lue, pour que la troncature ne finisse pas sur une marche. Les courbes montrent la réponse avec le fondu, le reste à zéro, et la réponse d'origine en gris. « Appliquer… » écrit un nouveau fichier audio que la configuration lira à la place de l'original, qui n'est pas modifié. 0 : pas de fondu. Les flèches changent la valeur d'un centième de la partie lue, avec ⌥ d'un échantillon.")) {
            VStack(alignment: .leading, spacing: 10) {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                    GridRow {
                        label(String(localized: "Montée"))
                        fadeStepper(\.fadeIn, length: length, other: model.fadeOut)
                    }
                    GridRow {
                        label(String(localized: "Descente"))
                        fadeStepper(\.fadeOut, length: length, other: model.fadeIn)
                    }
                }
                .font(.callout)
                HStack {
                    Button("Appliquer…") { model.showsFade = true }
                        .disabled(!model.hasFadeDraft || length < 2).controlSize(.small)
                    if model.hasFadeDraft {
                        Button("Annuler le fondu") { model.resetFade() }.controlSize(.small)
                    }
                }
            }
        }
    }

    /// A value in samples and the time it makes, with a stepper: a step is a hundredth of the part that is read (1 sample with ⌥), and the two fades
    /// together stay inside that part.
    private func fadeStepper(_ keyPath: ReferenceWritableKeyPath<AppModel, Int>, length: Int, other: Int) -> some View {
        let value = model[keyPath: keyPath]
        let room = max(length - other, 0)
        func step() -> Int { NSEvent.modifierFlags.contains(.option) ? 1 : max(1, length / 100) }
        return HStack(spacing: 8) {
            Text(verbatim: "\(value)").monospacedDigit().frame(width: Self.fieldWidth, alignment: .trailing)
            time(value)
            Stepper("", onIncrement: { model[keyPath: keyPath] = min(value + step(), room) },
                    onDecrement: { model[keyPath: keyPath] = max(value - step(), 0) })
                .labelsHidden()
        }
    }

    /// The two lengths together are no longer than the part that is read: a zone made shorter takes them back.
    private func clampFade() {
        guard let length = model.fadeContext()?.length else { return }
        let kept = ImpulseFade.clamped(fadeIn: model.fadeIn, fadeOut: model.fadeOut, length: length)
        if kept.fadeIn != model.fadeIn { model.fadeIn = kept.fadeIn }
        if kept.fadeOut != model.fadeOut { model.fadeOut = kept.fadeOut }
    }

    /// The width of the fields: the same for every row, and no wider than a number of this size needs.
    private static let fieldWidth: CGFloat = 84

    private func label(_ title: String) -> some View {
        Text(title).foregroundStyle(.secondary).lineLimit(1).fixedSize(horizontal: true, vertical: false)
    }

    private func time(_ frames: Int) -> some View {
        Text(verbatim: milliseconds(frames)).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
            .frame(minWidth: 62, alignment: .trailing)
    }

    private func field(_ text: Binding<String>, _ which: Field, submit: @escaping () -> Void) -> some View {
        TextField("", text: text)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .frame(width: Self.fieldWidth)
            .focused($focus, equals: which)
            .onSubmit(submit)
            .onChange(of: focus) { old, _ in if old == which { submit() } }
    }

    /// The texts follow the zone, except the one that is being typed in (unless `force`).
    private func syncTexts(force: Bool = false) {
        if force || focus != .start { startText = "\(start)" }
        if force || focus != .end { endText = "\(end)" }
    }

    private func commit(_ text: String, isStart: Bool) {
        guard let value = Int(text.trimmingCharacters(in: .whitespaces)) else { syncTexts(force: true); return }
        let wantedStart = isStart ? value : start, wantedEnd = isStart ? end : value
        // The fields show what is kept (a value outside the file is brought back), not what the zone was before: the zone of this view is
        // only updated once the new one is known to the window, so it cannot be read here.
        let kept = ImpulseZone.clamped(start: wantedStart, end: wantedEnd, total: total)
        startText = "\(kept.start)"
        endText = "\(kept.end)"
        apply(wantedStart, wantedEnd)
    }
}

/// A link in the colour of the application (the link style of the system takes its blue, whatever the tint is), dimmed when it is disabled.
private struct AccentLinkButton: View {
    @Environment(\.appAccentColor) private var accent
    @Environment(\.isEnabled) private var isEnabled
    let title: LocalizedStringKey
    let action: () -> Void

    init(_ title: LocalizedStringKey, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) { Text(title) }
            .buttonStyle(.plain)
            .foregroundStyle(accent)
            .opacity(isEnabled ? 1 : 0.4)
    }
}
