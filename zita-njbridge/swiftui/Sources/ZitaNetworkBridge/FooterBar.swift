// SPDX-License-Identifier: GPL-3.0-or-later

import AppearanceKit
import MatrixKit
import SwiftUI
import ZitaBridgeKit

/// The same on every page: under the sidebar and the page, over the whole width of the window, 98 points high.
struct FooterBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack {
            ArmGrid().frame(maxWidth: .infinity, alignment: .leading)

            if model.needsConfiguration {
                Button("Configurer la liaison") { model.page = .network }
                    .buttonStyle(.borderedProminent).accentTint().controlSize(.large)
                    .help("Saisissez l'adresse de la liaison avant de la démarrer.")
            } else {
                RoundButton()
            }

            CommandButton().frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 24)
        .frame(height: 98)
        .background(Color.windowFill)
        .overlay(alignment: .top) { Divider() }
    }
}

extension LinkDirection {
    var symbol: String { self == .receive ? "arrow.down.right.circle" : "arrow.up.right.circle" }

    /// Whether the settings of this direction allow it to start.
    @MainActor func canStart(in controller: BridgeController) -> Bool {
        self == .receive ? controller.receiver.canStart : controller.sender.canStart
    }
}

/// The two directions of the footer as a grid, so that the same things line up in both rows: the switch that arms the direction, its
/// name, a LED for where it is, a round button to start or stop it alone, and, when its settings changed, the button that applies them.
struct ArmGrid: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            row(.receive)
            row(.send)
        }
    }

    @ViewBuilder
    private func row(_ direction: LinkDirection) -> some View {
        let controller = model.controller
        let armed = controller.isArmed(direction)
        let running = controller.isRunning(direction)
        GridRow {
            Toggle(isOn: Binding(
                get: { controller.isArmed(direction) },
                set: { if direction == .receive { controller.receiveArmed = $0 } else { controller.sendArmed = $0 } }
            )) { EmptyView() }
                .toggleStyle(.switch).labelsHidden().accentTint().controlSize(.small)
            Label(direction == .receive ? "Recevoir" : "Envoyer", systemImage: direction.symbol)
                .foregroundStyle(armed ? Color.primary : Color.secondary)
            StateLED(state: armed ? model.state(of: direction) : nil, direction: direction)
                .gridColumnAlignment(.center)
            // Start or stop this direction alone (the round button of the footer does both).
            RunButton(direction: direction)
                .disabled(!armed || (!running && !direction.canStart(in: controller)))
            if armed, controller.needsRestart(direction) {
                Button { controller.restart(direction) } label: {
                    Label("Appliquer", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent).tint(.orange).controlSize(.small)
                .help(direction == .receive ? "Des réglages de réception ont changé : redémarrez ce sens pour les appliquer."
                                            : "Des réglages d'envoi ont changé : redémarrez ce sens pour les appliquer.")
            }
        }
    }
}

/// The round button that starts or stops one direction. Under the pointer it swells a little and takes the accent, as the big round button
/// does; it dips when pressed.
struct RunButton: View {
    let direction: LinkDirection
    @Environment(AppModel.self) private var model
    @Environment(\.appAccentColor) private var accent
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false
    @State private var flashing = false

    var body: some View {
        let controller = model.controller
        let running = controller.isRunning(direction)
        let lit = (hovered && isEnabled) || flashing
        Button { if running { controller.stop(direction) } else { controller.start(direction) } } label: {
            Image(systemName: running ? "stop.fill" : "play.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(lit ? Color.white : Color.primary)
                .frame(width: 26, height: 26)
                .background {
                    if lit {
                        Circle().fill(accent).shadow(color: accent.opacity(0.55), radius: 5)
                    } else {
                        Color.clear.glassCircle()
                    }
                }
                .scaleEffect(lit ? 1.12 : 1)
        }
        .buttonStyle(PressStyle())
        .onHover { h in withAnimation(.spring(duration: 0.2, bounce: 0.3)) { hovered = h } }
        // Asked to show itself (a link in a text of a page): it lights up and swells three times, even when it is disabled.
        .onChange(of: model.flashCount) { _, _ in
            guard model.flashedDirection == direction else { return }
            Task {
                for _ in 0..<3 {
                    withAnimation(.easeInOut(duration: 0.28)) { flashing = true }
                    try? await Task.sleep(for: .milliseconds(380))
                    withAnimation(.easeInOut(duration: 0.28)) { flashing = false }
                    try? await Task.sleep(for: .milliseconds(300))
                }
            }
        }
        .help(running ? (direction == .receive ? "Arrêter la réception" : "Arrêter l'envoi")
                      : (direction == .receive ? "Démarrer la réception" : "Démarrer l'envoi"))
        .accessibilityLabel(running ? (direction == .receive ? "Arrêter la réception" : "Arrêter l'envoi")
                                    : (direction == .receive ? "Démarrer la réception" : "Démarrer l'envoi"))
    }
}

/// A small LED: grey when stopped, orange while waiting, green when linked (red when the program could not run). Not there at all
/// when the direction is not armed. The breathing of the orange one is made by Core Animation, so that waiting costs nothing.
struct StateLED: View {
    let state: LinkState?
    let direction: LinkDirection

    private var help: LocalizedStringKey {
        switch (direction, state) {
        case (_, nil): ""
        case (.receive, .stopped?): "Réception arrêtée"
        case (.receive, .waiting?): "Réception : en attente de l'émetteur"
        case (.receive, .syncing?): "Réception : synchronisation"
        case (.receive, .linked?): "Réception en cours"
        case (.send, .stopped?): "Envoi arrêté"
        case (.send, .linked?): "Envoi en cours"
        case (_, .failed?): "Le programme n'a pas pu démarrer"
        default: ""
        }
    }

    var body: some View {
        Group {
            if state == .linked {
                Circle().fill(color).frame(width: 9, height: 9).shadow(color: .green.opacity(0.7), radius: 3)
            } else {
                Circle().fill(color).frame(width: 9, height: 9)
            }
        }
        // Only synchronising breathes (it lasts a few seconds): waiting can last for hours, and an animation that long wastes energy.
        .modifier(Breathing(active: state == .syncing, period: 0.7))
        .opacity(state == nil ? 0 : 1)
        .help(help)
        .accessibilityHidden(state == nil)
    }

    private var color: Color {
        switch state {
        case .waiting?, .syncing?: .orange
        case .linked?: .green
        case .failed?: .red
        default: Color.secondary.opacity(0.5)
        }
    }
}

/// A fade that repeats while `active`. It runs in Core Animation: no view is drawn again for each step, as it would be with a
/// timeline (a ring drawn again 24 times a second, with its shadow, used all of a processor).
struct Breathing: ViewModifier {
    let active: Bool
    var period: Double = 1.0
    @State private var low = false

    func body(content: Content) -> some View {
        content
            .opacity(active && low ? 0.3 : 1)
            .animation(active ? .easeInOut(duration: period / 2).repeatForever(autoreverses: true) : .easeOut(duration: 0.2), value: low)
            .onAppear { if active { low = true } }
            .onChange(of: active) { _, now in low = now }
    }
}

/// The round button: starts what is armed, stops it all when something runs. Around it, a ring (one direction) or two half rings
/// (left receives, right sends) say where each link is. At rest the glyph says the state; under the pointer it says the action.
struct RoundButton: View {
    @Environment(AppModel.self) private var model
    @Environment(\.appAccentColor) private var accent
    @State private var hovered = false

    var body: some View {
        let controller = model.controller
        let armed = controller.armedDirections
        let state = model.aggregateState
        let running = controller.anyArmedRuns
        Button { controller.toggleAll() } label: {
            Glyph(state: state, action: hovered ? (running ? .stop : .play) : nil)
                .foregroundStyle(.white)
                .frame(width: 62, height: 62)
                .accentGlassDisc(accent)
                .scaleEffect(hovered ? 1.05 : 1)
        }
        .buttonStyle(PressStyle())
        .disabled(armed.isEmpty)
        .overlay {
            StateRing(receive: controller.receiveArmed ? model.state(of: .receive) : nil,
                      send: controller.sendArmed ? model.state(of: .send) : nil)
        }
        .onHover { h in withAnimation(.spring(duration: 0.22, bounce: 0.3)) { hovered = h } }
        .help(armed.isEmpty ? "Choisissez Recevoir, Envoyer ou les deux." : running ? "Arrêter" : "Démarrer")
        .accessibilityLabel(running ? "Arrêter" : "Démarrer")
    }
}

/// The bolt, in its state: `bolt.fill` stopped, with a clock while waiting, with a check when linked. Under the pointer, the bolt
/// with the badge of the action.
struct Glyph: View {
    enum Action { case play, stop }
    let state: LinkState
    let action: Action?

    var body: some View {
        ZStack {
            Image(systemName: symbol).font(.system(size: 28, weight: .medium))
            if let action {
                Image(systemName: action == .play ? "play.circle.fill" : "stop.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .offset(x: 10, y: 10)
            }
        }
    }

    private var symbol: String {
        if action != nil { return "bolt.fill" }
        switch state {
        case .waiting, .syncing: return "bolt.badge.clock.fill"
        case .linked: return "bolt.badge.checkmark.fill"
        default: return "bolt.fill"
        }
    }
}

/// The ring around the round button. A nil state means the direction is not armed. Orange dashes while it waits (still: waiting can last
/// for hours), a solid orange ring that breathes while it synchronises, green when linked.
struct StateRing: View {
    let receive: LinkState?
    let send: LinkState?

    private enum Part { case full, left, right }

    var body: some View {
        ZStack {
            if let receive { arc(receive, part: send == nil ? .full : .left) }
            if let send { arc(send, part: receive == nil ? .full : .right) }
        }
        .frame(width: 78, height: 78)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func arc(_ state: LinkState, part: Part) -> some View {
        let range: ClosedRange<Double> = part == .full ? 0...1 : 0.012...0.488
        // trim starts at 3 o'clock and runs clockwise: turned a quarter, a half starts at the top (right half) or at the bottom (left half).
        let turn: Double = part == .right ? -90 : part == .left ? 90 : 0
        let style = StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: state == .waiting ? [5, 5] : [])
        let ring = Circle().trim(from: range.lowerBound, to: range.upperBound).stroke(color(state), style: style).rotationEffect(.degrees(turn))
        Group {
            if state == .linked { ring.shadow(color: .green.opacity(0.6), radius: 5) } else { ring }
        }
        .opacity(state == .stopped ? 0.45 : 1)
        .modifier(Breathing(active: state == .syncing, period: 0.7))
    }

    private func color(_ state: LinkState) -> Color {
        switch state {
        case .waiting, .syncing: .orange
        case .linked: .green
        case .failed: .red
        case .stopped: Color.secondary
        }
    }
}

// MARK: Command line

struct CommandButton: View {
    @State private var showsCommand = false

    var body: some View {
        Button("Ligne de commande générée") { showsCommand = true }
            .sheet(isPresented: $showsCommand) { CommandSheet() }
    }
}

struct CommandSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    /// One line for each direction that is armed (both when none is).
    private var text: String {
        let c = model.controller
        var lines = [String]()
        let directions = c.armedDirections.isEmpty ? [LinkDirection.receive, .send] : c.armedDirections
        for d in directions { lines.append(d == .receive ? c.receiver.command.display() : c.sender.command.display()) }
        return lines.joined(separator: "\n\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Ligne de commande équivalente").font(.title3).fontWeight(.semibold)
                Text("Ce que Zita Network Bridge lance, un programme par sens (la réception avec --info, dont l'application lit les valeurs). Les branchements sont faits ensuite par l'application.")
                    .foregroundStyle(.secondary)
            }
            // The terminal view is dark in both appearances, with the colours of a shell.
            ScrollView {
                Text(CommandHighlighter.attributed(text))
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(minHeight: 80, maxHeight: 280)
            .background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.12), lineWidth: 0.5))
            HStack {
                Spacer()
                Button(copied ? "Copié" : "Copier") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    copied = true
                }
                Button("Fermer") { dismiss() }.keyboardShortcut(.defaultAction).accentTint()
            }
        }
        .padding(20)
        .frame(width: 560)
    }
}
