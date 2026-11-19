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
            VStack(alignment: .leading, spacing: 9) {
                ArmRow(direction: .receive)
                ArmRow(direction: .send)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if model.needsConfiguration {
                Button("Configurer la liaison") { model.page = .network }
                    .buttonStyle(.borderedProminent).accentTint().controlSize(.large)
                    .help("Saisir l'adresse de la liaison avant de la démarrer.")
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
}

/// A switch that arms a direction, with its picto and a LED for where it is.
struct ArmRow: View {
    let direction: LinkDirection
    @Environment(AppModel.self) private var model

    var body: some View {
        let controller = model.controller
        let armed = controller.isArmed(direction)
        HStack(spacing: 10) {
            Toggle(isOn: Binding(
                get: { controller.isArmed(direction) },
                set: { if direction == .receive { controller.receiveArmed = $0 } else { controller.sendArmed = $0 } }
            )) { EmptyView() }
                .toggleStyle(.switch).labelsHidden().accentTint().controlSize(.small)
            Label(direction == .receive ? "Recevoir" : "Envoyer", systemImage: direction.symbol)
                .frame(width: 96, alignment: .leading)
                .foregroundStyle(armed ? Color.primary : Color.secondary)
            StateLED(state: armed ? model.state(of: direction) : nil, direction: direction)
        }
    }
}

/// A small LED: grey when stopped, orange while waiting, green when linked (red when the program could not run). Not there at all
/// when the direction is not armed.
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
        TimelineView(.animation(minimumInterval: 1.0 / 20)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let pulse = 0.55 + 0.45 * abs(sin(t * .pi / 1.0))
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
                .opacity(state == .waiting || state == .syncing ? pulse : 1)
                .shadow(color: glow, radius: 3)
        }
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
    private var glow: Color { state == .linked ? .green.opacity(0.7) : .clear }
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
                .frame(width: 72, height: 72)
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
            Image(systemName: symbol).font(.system(size: 32, weight: .medium))
            if let action {
                Image(systemName: action == .play ? "play.circle.fill" : "stop.circle.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .background(Circle().fill(.black.opacity(0.0)))
                    .offset(x: 12, y: 12)
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

/// The ring around the round button. A nil state means the direction is not armed.
struct StateRing: View {
    let receive: LinkState?
    let send: LinkState?

    private enum Part { case full, left, right }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack {
                if let receive { arc(receive, part: send == nil ? .full : .left, t) }
                if let send { arc(send, part: receive == nil ? .full : .right, t) }
            }
        }
        .frame(width: 88, height: 88)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func arc(_ state: LinkState, part: Part, _ t: Double) -> some View {
        let range: ClosedRange<Double> = part == .full ? 0...1 : 0.012...0.488
        // trim starts at 3 o'clock and runs clockwise: turned a quarter, a half starts at the top (right half) or at the bottom (left half).
        let turn: Double = part == .right ? -90 : part == .left ? 90 : 0
        let style: StrokeStyle = state == .waiting ? StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [5, 5], dashPhase: -t * 12) : StrokeStyle(lineWidth: 2.5, lineCap: .round)
        Circle()
            .trim(from: range.lowerBound, to: range.upperBound)
            .stroke(color(state), style: style)
            .rotationEffect(.degrees(turn))
            .opacity(state == .syncing ? 0.4 + 0.6 * abs(sin(t * .pi / 0.7)) : (state == .stopped ? 0.45 : 1))
            .shadow(color: state == .linked ? .green.opacity(0.6) : .clear, radius: 5)
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
                Button("Fermer") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560)
    }
}
