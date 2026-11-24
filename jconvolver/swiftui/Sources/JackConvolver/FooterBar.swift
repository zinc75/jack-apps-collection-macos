// SPDX-License-Identifier: GPL-3.0-or-later

import AppearanceKit
import JConvolverKit
import MatrixKit
import AppKit
import QuartzCore
import SwiftUI

/// The same on every page: under the sidebar and the page, over the whole width of the window, 98 points high. On the left, two chips side
/// by side (the state, the mode); in the middle the round button; on the right the command line.
struct FooterBar: View {
    var body: some View {
        HStack {
            StatusColumn().frame(maxWidth: .infinity, alignment: .leading)
            RoundButton()
            CommandColumn().frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 24)
        .frame(height: 98)
        .background(Color.windowFill)
        .overlay(alignment: .top) { Divider() }
    }
}

/// On the left: the state and the mode in chips, and the load while the engine runs. What the configuration holds is in the card of the sidebar.
struct StatusColumn: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 8) {
            StatusPill()
            ModeChip()
            if model.controller.isRunning { LoadGauges().padding(.leading, 6).fixedSize().layoutPriority(1) }
        }
        // The chips are 28 points high; the three gauges one under the other are a little taller, and the whole fits in the 98 points of the footer.
        .frame(minHeight: 28)
    }
}

/// The mode, said as the state is: a chip of information (the mode is chosen on the home page).
struct ModeChip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: model.mode == .file ? "waveform.path" : "dot.radiowaves.left.and.right").foregroundStyle(.secondary)
            Text(model.mode == .file ? "Sur fichier audio" : "Temps réel")
        }
        .font(.callout)
        .padding(.horizontal, 12).frame(height: 28)
        .background(Color.primary.opacity(0.07), in: Capsule())
        .help("Le mode se choisit sur la page d'accueil")
    }
}

struct StatusPill: View {
    @Environment(AppModel.self) private var model

    private enum Kind { case ready, running, warning, error }

    private var content: (kind: Kind, symbol: String, text: LocalizedStringKey) {
        let c = model.controller
        switch c.state {
        case .running: return (.running, "checkmark.circle.fill", model.mode == .file ? "Traitement…" : "En cours d'exécution")
        case .stopping: return (.running, "checkmark.circle.fill", "Arrêt…")
        case .ended where c.endedOnAProblem: return (.error, "exclamationmark.circle.fill", "Le moteur s'est arrêté")
        default: break
        }
        guard model.isOpen else { return (.ready, "circle", "Aucune configuration ouverte") }
        let count = model.problems.count
        let toFix: LocalizedStringKey = count == 1 ? "1 problème à régler" : "\(count) problèmes à régler"
        if model.hasErrors { return (.error, "exclamationmark.circle.fill", toFix) }
        if count > 0 { return (.warning, "exclamationmark.triangle.fill", toFix) }
        return (.ready, "checkmark.circle.fill", model.mode == .file ? "Prêt à traiter" : "Prêt à lancer")
    }

    var body: some View {
        let state = content
        let color: Color = switch state.kind { case .ready, .running: .green; case .warning: .orange; case .error: .red }
        Button {
            // The pill says what is wrong: the problems to settle open their list; the log opens when the engine stopped on a problem.
            if model.controller.endedOnAProblem { model.page = .log } else if !model.problems.isEmpty { model.showsProblems = true }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: state.symbol).foregroundStyle(color)
                Text(state.text)
            }
            .font(.callout)
            .padding(.horizontal, 12).frame(height: 28)
            .background(state.kind == .ready ? Color.primary.opacity(0.07) : color.opacity(0.16), in: Capsule())
        }
        .buttonStyle(.plain)
        .opacity(model.isOpen || model.controller.isRunning ? 1 : 0.6)
    }
}

/// The load of JACK, the load of the engine over the whole machine, and the audio cuts, one under the other so that the bars line up. A click on the
/// cuts opens the journal.
struct LoadGauges: View {
    @Environment(AppModel.self) private var model
    @Environment(\.appAccentColor) private var accent

    private static let barWidth: CGFloat = 56
    private static let valueWidth: CGFloat = 36

    var body: some View {
        let controller = model.controller
        Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 2) {
            // The audio load of the server, which is what tells that the engine is too heavy for the period: only in real time, and when JACK says it.
            if model.mode == .realTime, let load = model.jack.cpuLoad {
                let tint: Color = load >= 90 ? .red : load >= 70 ? .orange : accent
                GridRow {
                    Text("JACK").foregroundStyle(.secondary).lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    ProgressView(value: min(1, load / 100)).progressViewStyle(.linear).frame(width: Self.barWidth).tint(tint)
                    Text(verbatim: "\(Int(load.rounded())) %").monospacedDigit().foregroundStyle(load >= 90 ? Color.red : Color.primary)
                        .frame(width: Self.valueWidth, alignment: .trailing)
                }
                .help("Charge audio de JACK : la part du temps d'une période que le traitement prend. Orange à partir de 70 %, rouge à partir de 90 % : au-delà, les coupures (xruns) arrivent.")
            }
            let share = controller.machineShare ?? 0
            GridRow {
                Text("Moteur").foregroundStyle(.secondary).lineLimit(1).fixedSize(horizontal: true, vertical: false)
                ProgressView(value: min(1, share)).progressViewStyle(.linear).frame(width: Self.barWidth).tint(accent)
                Text(verbatim: share < 0.01 ? "< 1 %" : "\(Int((share * 100).rounded())) %").monospacedDigit()
                    .frame(width: Self.valueWidth, alignment: .trailing)
            }
            .help(helpText(controller))
            GridRow {
                Text("xruns").foregroundStyle(.secondary).lineLimit(1).fixedSize(horizontal: true, vertical: false)
                Color.clear.frame(width: Self.barWidth, height: 1)
                Button { model.page = .log } label: {
                    Text(verbatim: "\(controller.xruns)").monospacedDigit().foregroundStyle(controller.xruns > 0 ? Color.red : Color.primary)
                        .frame(width: Self.valueWidth, alignment: .trailing)
                }
                .buttonStyle(.plain)
            }
            .help("Coupures audio depuis le lancement. Cliquez sur le nombre pour voir le journal.")
        }
        .font(.caption)
    }

    private func helpText(_ controller: EngineController) -> LocalizedStringKey {
        let cores = controller.cores ?? 0
        let all = ProcessInfo.processInfo.activeProcessorCount
        return "CPU du moteur : \(cores.formatted(.number.precision(.fractionLength(1)))) cœur sur \(all)"
    }
}

/// The round button: starts the engine, stops it while it runs.
struct RoundButton: View {
    @Environment(AppModel.self) private var model
    @Environment(\.appAccentColor) private var accent
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let running = model.controller.isRunning
        let blocked = !model.isOpen || (!running && model.hasErrors)
        Button { model.toggleRun() } label: {
            // The gear turns while the engine runs; a click still stops it (the help says so). The turn is played by Core Animation,
            // out of SwiftUI: a symbol effect made the whole window redraw at each frame (about 11 % of a core).
            SpinningGear(spinning: running && !reduceMotion)
                .frame(width: 62, height: 62)
                .accentGlassDisc(accent)
        }
        .buttonStyle(PressStyle())
        .disabled(blocked)
        .opacity(blocked ? 0.5 : 1)
        .accessibilityLabel(Text(LocalizedStringKey(running ? "Arrêter" : "Lancer")))
        .help(running ? "Arrêter" : (model.hasErrors ? "Il reste des points à régler" : "Lancer"))
    }
}

/// A white gear that turns forever while `spinning`, with the turn played by Core Animation on a layer, so that the render server
/// does the work and SwiftUI is not asked to redraw anything. It does not take clicks: the button around it does.
struct SpinningGear: NSViewRepresentable {
    var spinning: Bool
    var pointSize: CGFloat = 32
    /// Seconds for one turn.
    var period: Double = 2.4

    func makeNSView(context: Context) -> GearView { GearView(pointSize: pointSize, period: period) }
    func updateNSView(_ view: GearView, context: Context) { view.setSpinning(spinning) }
}

final class GearView: NSView {
    private let gear = CALayer()
    private let period: Double
    private var spinning = false
    private static let key = "spin"

    init(pointSize: CGFloat, period: Double) {
        self.period = period
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
            .applying(.init(paletteColors: [.white]))
        if let symbol = NSImage(systemSymbolName: "gearshape.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
            gear.contents = symbol.cgImage(forProposedRect: nil, context: nil, hints: nil)
            gear.bounds = CGRect(origin: .zero, size: symbol.size)
        }
        gear.contentsGravity = .resizeAspect
        layer?.addSublayer(gear)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        gear.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        gear.contentsScale = window?.backingScaleFactor ?? 2
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        gear.contentsScale = window?.backingScaleFactor ?? 2
        if spinning { startTurning() }      // a layer animation is dropped when the view leaves its window
    }

    func setSpinning(_ on: Bool) {
        guard on != spinning else { return }
        spinning = on
        on ? startTurning() : stopTurning()
    }

    private func startTurning() {
        guard gear.animation(forKey: Self.key) == nil else { return }
        let turn = CABasicAnimation(keyPath: "transform.rotation.z")
        turn.fromValue = 0
        turn.toValue = -2 * Double.pi          // clockwise
        turn.duration = period
        turn.repeatCount = .infinity
        turn.timingFunction = CAMediaTimingFunction(name: .linear)
        turn.isRemovedOnCompletion = false
        gear.add(turn, forKey: Self.key)
    }

    /// Stops where the gear is, with a short slowing down instead of a cut.
    private func stopTurning() {
        let angle = (gear.presentation()?.value(forKeyPath: "transform.rotation.z") as? Double) ?? 0
        gear.removeAnimation(forKey: Self.key)
        let end = angle - 0.5
        gear.setValue(end, forKeyPath: "transform.rotation.z")
        let slow = CABasicAnimation(keyPath: "transform.rotation.z")
        slow.fromValue = angle
        slow.toValue = end
        slow.duration = 0.5
        slow.timingFunction = CAMediaTimingFunction(name: .easeOut)
        gear.add(slow, forKey: "slow")
    }
}

/// On the right: the command line, a button as in the other applications of the collection.
struct CommandColumn: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button("Ligne de commande générée") { model.showsCommand = true }
            .disabled(!model.isOpen)
    }
}
