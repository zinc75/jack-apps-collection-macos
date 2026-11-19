// SPDX-License-Identifier: GPL-3.0-or-later

import AppearanceKit
import MatrixKit
import SwiftUI
import ZitaBridgeKit

/// The page of the link: one block for each direction that is armed.
struct LinkView: View {
    @Environment(AppModel.self) private var model

    @Environment(\.appAccentColor) private var accent

    var body: some View {
        let controller = model.controller
        if controller.armedDirections.isEmpty {
            NoDirectionView()
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    if controller.receiveArmed { ReceiveBlock() }
                    if controller.sendArmed { SendBlock() }
                }
                .padding(.horizontal, 26).padding(.vertical, 18)
            }
            .softScrollEdges()
            // The links of the texts of this page ("zita://flash/receive") make the start button of the direction flash.
            .tint(accent)
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == "zita", url.host == "flash", let direction = LinkDirection(rawValue: url.lastPathComponent) else { return .systemAction }
                model.flash(direction)
                return .handled
            })
        }
    }
}

// MARK: Header of a direction

/// The state of a direction in words. Starting and stopping are in the footer, next to the switch of the direction.
struct DirectionHeader: View {
    let direction: LinkDirection
    let title: LocalizedStringKey
    let state: LinkState
    let detail: Text
    let where_: Text

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                StateLED(state: state, direction: direction).scaleEffect(1.35).frame(width: 14)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 28, weight: .light))
                    detail.font(.callout).foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
            }
            where_.font(.callout).foregroundStyle(.secondary)
        }
    }
}

private func number(_ value: Double, digits: Int = 1) -> String {
    value.formatted(.number.precision(.fractionLength(digits)))
}

/// A small caption and a value, in a grid.
struct Fact: View {
    let title: LocalizedStringKey
    let value: String
    var unit: LocalizedStringKey?
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(verbatim: value).font(.system(size: 15, weight: .medium).monospacedDigit())
                if let unit { Text(unit).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: Receiving

struct ReceiveBlock: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let controller = model.controller
        let r = controller.receiver
        let state = r.state
        DirectionContainer(direction: .receive, detail: "Ce Mac reçoit du son depuis le réseau") {
            DirectionHeader(direction: .receive, title: title(state), state: state, detail: detail(state),
                            where_: Text("Écoute sur **\(r.settings.address.isEmpty ? "—" : r.settings.address) : \(r.settings.port)**"))
            Group {
                MarginCard()
                ReceiveDetails()
            }
            .opacity(state.isRunning ? 1 : 0.45)
        }
    }

    private func title(_ state: LinkState) -> LocalizedStringKey {
        switch state {
        case .stopped: "Arrêté"
        case .waiting: "En attente"
        case .syncing: "Synchronisation"
        case .linked: "Réception"
        case .failed: "Échec"
        }
    }

    private func detail(_ state: LinkState) -> Text {
        let r = model.controller.receiver
        switch state {
        case .stopped: return Text("Réception à l'arrêt. Lancez-la avec \(Image(systemName: "play.fill")) [en bas de la fenêtre](zita://flash/receive).")
        case .waiting:
            if let delay = r.retryDelay { return Text("Nouvel essai dans \(number(delay, digits: 0)) s…") }
            return Text("En attente du premier paquet de l'émetteur…")
        case .syncing: return Text("L'émetteur est trouvé : réglage du tampon et du rééchantillonneur…")
        case .linked:
            let s = r.sender
            return Text("depuis \(s?.address ?? "—") · \(s?.channels ?? 0) voies · \((s?.rate ?? 0).formatted(.number.grouping(.automatic))) Hz")
        case .failed(let text): return Text(verbatim: text)
        }
    }
}

struct MarginCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.appAccentColor) private var accent

    var body: some View {
        let controller = model.controller
        let r = controller.receiver
        let live = r.state == .linked
        let assessment = BufferAdvice.assess(history: r.marginHistory)
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Label("Marge du tampon", systemImage: LinkDirection.receive.symbol).font(.headline)
                    Text("les échantillons qui restent en réserve avant que le tampon soit vide").font(.caption).foregroundStyle(.secondary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(verbatim: live ? number(r.margin ?? 0) : "–").font(.system(size: 52, weight: .ultraLight).monospacedDigit())
                            .frame(minWidth: 110, alignment: .leading)
                        Text("ms").font(.system(size: 18)).foregroundStyle(.secondary)
                    }
                    if live, let s = r.statistics {
                        Text("\(s.frames.formatted(.number.grouping(.automatic))) échantillons").font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Chip(text: Text("Interruptions : \(r.interruptions)"), kind: r.interruptions > 0 ? .bad : .plain)
                    Button("Remettre à zéro") { r.resetInterruptions() }
                }
                MarginGauge(value: live ? r.margin : nil)
                MarginSparkline(history: r.marginHistory, accent: accent)
                BufferSetting()
                Advice(assessment: assessment, live: live)
            }
        }
    }
}

/// The extra buffer, next to the margin it acts on: what it is now (and, when it was just changed, what it will be once the program has
/// started again), and a way to the setting.
struct BufferSetting: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let r = model.controller.receiver
        let now = r.runningSettings?.bufferMilliseconds ?? r.settings.bufferMilliseconds
        let next = r.settings.bufferMilliseconds
        HStack(spacing: 8) {
            Label("Tampon supplémentaire", systemImage: "clock.arrow.circlepath").foregroundStyle(.secondary)
            Text("\(now) ms").fontWeight(.semibold).monospacedDigit()
            if r.runningSettings != nil, next != now {
                Text("→ \(next) ms après le redémarrage").foregroundStyle(.orange)
            }
            Spacer()
            Button("Régler…") { model.page = .flow }
        }
        .font(.callout)
    }
}

/// The scale of the margin, in milliseconds: red when it is empty, orange when it is short, green beyond.
struct MarginGauge: View {
    let value: Double?
    private let low = -5.0, high = 40.0

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { proxy in
                let w = proxy.size.width
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(LinearGradient(stops: [.init(color: .red, location: 0), .init(color: .red, location: 0.12), .init(color: .orange, location: 0.12),
                                                     .init(color: .orange, location: 0.26), .init(color: .green, location: 0.26), .init(color: .green, location: 1)],
                                             startPoint: .leading, endPoint: .trailing))
                        .opacity(0.85)
                        .frame(height: 12)
                    if let value {
                        let x = CGFloat(min(max((value - low) / (high - low), 0), 1)) * w
                        RoundedRectangle(cornerRadius: 2).fill(Color.primary).frame(width: 4, height: 20)
                            .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Color.windowFill, lineWidth: 1.5))
                            .offset(x: x - 2)
                            .animation(.easeOut(duration: 0.2), value: value)
                    }
                }
                .frame(height: 20)
            }
            .frame(height: 20)
            HStack {
                ForEach(["−5", "0", "5", "10", "20", "30", "40 ms"], id: \.self) { label in
                    Text(verbatim: label)
                    if label != "40 ms" { Spacer() }
                }
            }
            .font(.system(size: 10).monospacedDigit()).foregroundStyle(.secondary)
        }
    }
}

/// The last minute of the margin, with its scale: gridlines and values in milliseconds, the seconds under it, and the lowest and highest
/// values of the minute.
struct MarginSparkline: View {
    let history: [Double]
    let accent: Color
    private let lo = -8.0, hi = 44.0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Canvas { context, size in
                let left: CGFloat = 38, bottom: CGFloat = 16
                let plot = CGRect(x: left, y: 6, width: size.width - left - 6, height: size.height - 6 - bottom)
                func y(_ v: Double) -> CGFloat { plot.maxY - CGFloat((min(max(v, lo), hi) - lo) / (hi - lo)) * plot.height }
                func line(_ p: CGPoint, _ q: CGPoint, _ opacity: Double, dash: [CGFloat] = []) {
                    var path = Path(); path.move(to: p); path.addLine(to: q)
                    context.stroke(path, with: .color(.secondary.opacity(opacity)), style: StrokeStyle(lineWidth: 0.7, dash: dash))
                }
                func label(_ text: String, at point: CGPoint, anchor: UnitPoint) {
                    context.draw(Text(verbatim: text).font(.system(size: 9.5).monospacedDigit()).foregroundColor(.secondary), at: point, anchor: anchor)
                }
                // Horizontal: the margin, every 10 ms; the zero, where the sound is cut, is dashed and stronger.
                for v in [0.0, 10, 20, 30, 40] {
                    line(CGPoint(x: plot.minX, y: y(v)), CGPoint(x: plot.maxX, y: y(v)), v == 0 ? 0.6 : 0.2, dash: v == 0 ? [3, 3] : [])
                    label(v == 40 ? "40 ms" : "\(Int(v))", at: CGPoint(x: plot.minX - 6, y: y(v)), anchor: .trailing)
                }
                // Vertical: the seconds, every 15.
                for (i, name) in ["−60 s", "−45 s", "−30 s", "−15 s"].enumerated() {
                    let x = plot.minX + plot.width * CGFloat(i) / 4
                    line(CGPoint(x: x, y: plot.minY), CGPoint(x: x, y: plot.maxY), 0.12)
                    label(name, at: CGPoint(x: x, y: size.height - 2), anchor: i == 0 ? .bottomLeading : .bottom)
                }
                label(String(localized: "maintenant"), at: CGPoint(x: plot.maxX, y: size.height - 2), anchor: .bottomTrailing)
                guard history.count >= 2 else { return }
                let n = ReceiverModel.historyLength
                let dx = plot.width / CGFloat(n - 1), offset = n - history.count
                for i in 1..<history.count {
                    var segment = Path()
                    segment.move(to: CGPoint(x: plot.minX + CGFloat(offset + i - 1) * dx, y: y(history[i - 1])))
                    segment.addLine(to: CGPoint(x: plot.minX + CGFloat(offset + i) * dx, y: y(history[i])))
                    context.stroke(segment, with: .color(history[i] < 0 || history[i - 1] < 0 ? .red : accent), style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
                }
            }
            .frame(height: 140)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            if let low = history.min(), let high = history.max() {
                Text("Dernière minute : de \(number(low)) à \(number(high)) ms").font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel("Marge sur la dernière minute")
    }
}

/// What to do about the margin, from the JACK period and the buffer.
struct Advice: View {
    let assessment: MarginAssessment
    let live: Bool
    @Environment(AppModel.self) private var model

    var body: some View {
        let controller = model.controller
        let period = controller.graph.bufferSize
        let suggestion = BufferAdvice.suggestion(period: period, buffer: controller.receiver.settings.bufferMilliseconds, assessment: assessment)
        HStack(spacing: 10) {
            if live, let suggestion, let period {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text("Marge insuffisante : avec une période JACK de \(period.formatted(.number.grouping(.automatic))) trames, un tampon supplémentaire de **\(suggestion) ms** ou plus est recommandé.")
                    .font(.callout).foregroundStyle(.orange)
                Spacer(minLength: 8)
                Button("Régler le tampon") { model.page = .flow }
            } else if live, assessment == .tight || assessment == .dropping {
                Chip(text: Text("Marge juste"), kind: .warn)
                Text("Le réseau est irrégulier : le tampon est déjà celui que la période demande.").font(.callout).foregroundStyle(.secondary)
            } else if live, assessment == .comfortable {
                Chip(text: Text("Marge confortable"), kind: .ok)
                Text("Le tampon absorbe les retards du réseau.").font(.callout).foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: 28)
    }
}

struct ReceiveDetails: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let controller = model.controller
        let r = controller.receiver
        let live = r.state == .linked
        let sourceRate = r.sender?.rate, localRate = controller.graph.sampleRate
        let hz: LocalizedStringKey = "Hz"
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Label("Détails du lien", systemImage: LinkDirection.receive.symbol).font(.headline)
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
                    GridRow {
                        Fact(title: "Émetteur", value: sourceRate.map { $0.formatted(.number.grouping(.automatic)) } ?? "–", unit: hz)
                        Fact(title: "Ce Mac", value: localRate.map { $0.formatted(.number.grouping(.automatic)) } ?? "–", unit: hz)
                        Fact(title: "Filtre de rééchantillonnage", value: r.filterDelay.map { "\($0)" } ?? "–", unit: "échantillons")
                        Fact(title: "Correction du rapport", value: live ? signed(r.statistics?.ratioOffsetPPM ?? 0) : "–", unit: "ppm")
                    }
                    GridRow {
                        Fact(title: "Périodes par seconde", value: periods(localRate, controller.graph.bufferSize, live))
                        Fact(title: "Erreur de la boucle", value: live ? number(r.statistics?.meanError ?? 0) : "–", unit: "échantillons")
                        Fact(title: "Voies reçues", value: ChannelList.format(r.runningSettings?.effectiveChannels ?? r.settings.effectiveChannels),
                             unit: r.sender.map { LocalizedStringKey("sur \($0.channels)") })
                        Fact(title: "Rééchantillonnage", value: resampling(sourceRate, localRate))
                    }
                }
            }
        }
    }

    private func signed(_ ppm: Double) -> String { (ppm >= 0 ? "+" : "") + number(ppm, digits: 0) }
    private func periods(_ rate: Int?, _ period: Int?, _ live: Bool) -> String {
        guard live, let rate, let period, period > 0 else { return "–" }
        return number(Double(rate) / Double(period))
    }
    private func resampling(_ source: Int?, _ local: Int?) -> String {
        guard let source, let local else { return "–" }
        return source == local ? String(localized: "aucun") : "\(source.formatted(.number.grouping(.automatic))) → \(local.formatted(.number.grouping(.automatic)))"
    }
}

// MARK: Sending

struct SendBlock: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let controller = model.controller
        let s = controller.sender
        let state = s.state
        DirectionContainer(direction: .send, detail: "Ce Mac envoie du son vers le réseau") {
            DirectionHeader(direction: .send, title: title(state), state: state, detail: detail(state),
                            where_: Text("Envoi vers **\(s.settings.address.isEmpty ? "—" : s.settings.address) : \(s.settings.port)**"))
            Group {
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Flux envoyé", systemImage: LinkDirection.send.symbol).font(.headline)
                        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
                            GridRow {
                                Fact(title: "Destinataire", value: s.settings.address.isEmpty ? "–" : s.settings.address)
                                Fact(title: "Port", value: "\(s.settings.port)")
                                Fact(title: "Voies", value: "\(s.settings.channels)")
                                Fact(title: "Format", value: format(s.settings.format))
                            }
                        }
                    }
                }
                Card {
                    Text("L'émetteur ne reçoit aucun retour du récepteur : l'état et la marge du lien se lisent **sur le Mac qui reçoit**. Si le son se coupe à l'arrivée, c'est là-bas que le tampon se règle.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            .opacity(state.isRunning ? 1 : 0.45)
        }
    }

    private func title(_ state: LinkState) -> LocalizedStringKey {
        switch state {
        case .stopped, .waiting, .syncing: "Arrêté"
        case .linked: "Envoi en cours"
        case .failed: "Échec"
        }
    }

    private func detail(_ state: LinkState) -> Text {
        let s = model.controller.sender.settings
        switch state {
        case .linked: return Text("vers \(s.address) : \(s.port) · \(s.channels) voies · \(format(s.format))")
        case .failed(let text): return Text(verbatim: text)
        default: return Text("Envoi à l'arrêt. Lancez-le avec \(Image(systemName: "play.fill")) [en bas de la fenêtre](zita://flash/send).")
        }
    }

    private func format(_ f: SampleFormat) -> String {
        switch f {
        case .bits16: String(localized: "16 bits")
        case .bits24: String(localized: "24 bits")
        case .float32: String(localized: "flottant 32 bits")
        }
    }
}
