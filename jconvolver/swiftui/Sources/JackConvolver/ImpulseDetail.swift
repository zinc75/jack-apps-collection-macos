// SPDX-License-Identifier: GPL-3.0-or-later

import AppearanceKit
import JConvolverKit
import PlotKit
import SoundFileKit
import SwiftUI

/// Which impulse response the detail window shows: the one at this place of this pair.
struct DetailTarget: Identifiable, Equatable {
    let pair: ConvPair
    let index: Int
    var id: String { "\(pair.input)-\(pair.output)-\(index)" }
}

/// The detail of an impulse response that comes from a sound file, in a window of its own: the waveform with the part the engine
/// reads and what the analysis found (where the attack starts, where the useful tail ends), the frequency response and the phase or
/// the group delay, drawn by PlotKit with the tools of its toolbar and an inspector for how the curves are shown.
struct ImpulseDetailWindow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.appAccentColor) private var accent

    private enum Kind: String { case time, spectrum, phase }

    @State private var kind: Kind = .time
    @State private var data: CurveData?
    @State private var pyramid: PeakPyramid?
    @State private var response: FrequencyResponse?
    @State private var failed = false
    @State private var analysis: ImpulseAnalysis?
    @State private var info: SoundFileInfo?
    @State private var controller = PlotController()
    @State private var series = PlotSeriesSet(count: 1)
    @State private var time = PlotViewport.signal(count: 2)
    @State private var spectrum = PlotViewport.signal(count: 2)
    @State private var phase = PlotViewport.signal(count: 2)
    /// How the vertical axis is drawn in each view: kept when one goes from a view to another.
    @State private var yScales: [Kind: AmplitudeScale] = [.time: .linear, .spectrum: .decibels(floor: -120), .phase: .linear]

    private var impulse: ConvImpulse? {
        guard let target = model.detail, let list = model.document?.impulses(at: target.pair), list.indices.contains(target.index) else { return nil }
        return list[target.index]
    }

    private var resolved: (path: String, channel: Int)? {
        guard let impulse, case .file(let file, let channel) = impulse.source else { return nil }
        return (ConvConfig.path(of: file, directory: impulse.directory, configDirectory: model.configDirectory), channel)
    }

    /// The part of the file the engine reads, in frames.
    private var used: Range<Int>? {
        guard let impulse, let total = data?.count else { return nil }
        let start = min(impulse.offset, total)
        let end = impulse.length > 0 ? min(impulse.offset + impulse.length, total) : total
        return start..<max(end, start)
    }

    private var loadKey: String { "\(resolved?.path ?? "")#\(resolved?.channel ?? 0)" }
    private struct ResponseKey: Hashable { var load: String; var used: Range<Int>? }

    var body: some View {
        Group {
            if let impulse, let resolved, let target = model.detail {
                VStack(alignment: .leading, spacing: 10) {
                    header(resolved, target)
                    tabs(impulse)
                    facts(impulse)
                }
                .padding(14)
            } else {
                Text("Cette RI n'existe plus.").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .inspector(isPresented: Bindable(controller).showsInspector) {
            PlotInspector(controller: controller, labels: .localized, accent: accent).inspectorColumnWidth(min: 230, ideal: 260, max: 340)
        }
        .navigationTitle(String(localized: "Détail de la RI"))
        .navigationSubtitle(resolved.map { ($0.path as NSString).lastPathComponent } ?? "")
        .toolbar { PlotToolbarContent(controller: controller, labels: .localized, accent: accent) }
        .task(id: loadKey) { await load() }
        .task(id: ResponseKey(load: loadKey, used: used)) { await computeResponse() }
        .onChange(of: controller.yScale) { _, new in if kind != .phase { yScales[kind] = new } }
        .onAppear {
            controller.hasInspector = true
            controller.series = series
            #if DEBUG
            let env = ProcessInfo.processInfo.environment
            if let v = env["JACKCONVOLVER_DETAIL"].flatMap(Kind.init(rawValue:)) { kind = v }
            if !(env["JACKCONVOLVER_INSPECTOR"] ?? "").isEmpty { controller.showsInspector = true }
            if !(env["JACKCONVOLVER_GROUPDELAY"] ?? "").isEmpty { controller.display.showGroupDelay = true }
            if let d = Int(env["JACKCONVOLVER_SMOOTH"] ?? ""), let s = OctaveSmoothing(rawValue: d) { controller.display.smoothing = s }
            #endif
        }
        // Closing the window forgets the target, so that the same response can be asked for again.
        .onDisappear { model.detail = nil }
    }

    private func header(_ resolved: (path: String, channel: Int), _ target: DetailTarget) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: "\((resolved.path as NSString).lastPathComponent) · \(String(localized: "voie")) \(resolved.channel)").font(.headline)
            Text("\(model.inputLabel(target.pair.input)) → \(model.outputLabel(target.pair.output))").foregroundStyle(.secondary)
            if let info {
                Text(verbatim: "\(info.container) · \(info.encoding) · \(Int(info.sampleRate)) Hz · \(info.channels) " + String(localized: "voies"))
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: The plots

    /// The three views are tabs over the plot, in a container, in the accent of the application (the tab view of the system keeps
    /// its own accent): the toolbar keeps the tools of the plot only.
    private func tabs(_ impulse: ConvImpulse) -> some View {
        VStack(spacing: 8) {
            Picker("Vue", selection: $kind) {
                Text("Temps").tag(Kind.time)
                Text("Fréquence").tag(Kind.spectrum)
                Text("Phase").tag(Kind.phase)
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize().accentTint()
            .padding(.top, 10)
            Group {
                if data != nil, pyramid != nil { plot } else if failed {
                    Text("Ce fichier ne peut pas être lu.").foregroundStyle(.red).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding([.horizontal, .bottom], 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
    }

    @ViewBuilder private var plot: some View {
        if let data, let pyramid {
            switch kind {
            case .time:
                SignalPlot(signal: pyramid, viewport: $time, sampleRate: data.sampleRate, amplitude: yScales[.time] ?? .linear, accent: accent,
                           labels: .localized, controller: controller, annotations: annotations)
            case .spectrum:
                if response != nil {
                    CurvePlot(curves: magnitudeCurves, viewport: $spectrum, xUnit: "Hz", yScale: yScales[.spectrum] ?? .decibels(floor: -120),
                              accent: accent, labels: .localized, controller: controller)
                } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            case .phase:
                if response != nil {
                    CurvePlot(curves: phaseCurves, viewport: $phase, xUnit: "Hz", yUnit: "°", accent: accent, labels: .localized,
                              controller: controller, yScaleSwitchable: false)
                } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            }
        }
    }

    /// The part the engine reads stands out, and the attack and the end of the tail are marked.
    private var annotations: PlotAnnotations {
        var a = PlotAnnotations()
        if let used, used.upperBound > used.lowerBound { a.highlighted = Double(used.lowerBound)...Double(used.upperBound) }
        if let analysis {
            a.markers = [PlotMarker(id: "attack", x: Double(analysis.attackFrame), name: String(localized: "attaque"), color: .green),
                         PlotMarker(id: "tail", x: Double(analysis.tailFrame), name: String(localized: "fin utile"), color: .orange)]
        }
        return a
    }

    private var magnitudeCurves: [PlotCurve] {
        guard let response else { return [] }
        return series.curves({ _ in (response.frequencies, response.magnitudes) }, isMagnitude: true)
    }

    private var phaseCurves: [PlotCurve] {
        guard let response else { return [] }
        return series.curves({ _ in (response.frequencies, response.phases) }, filled: false, phase: .degrees,
                             groupDelay: { _ in response.groupDelays })
    }

    // MARK: The figures

    private func facts(_ impulse: ConvImpulse) -> some View {
        let rate = info?.sampleRate ?? 0
        func time(_ frames: Int) -> String {
            guard rate > 0 else { return "" }
            return "\(frames) (" + (Double(frames) / rate * 1000).formatted(.number.precision(.fractionLength(1))) + " ms)"
        }
        return HStack(alignment: .top, spacing: 40) {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 4) {
                if let info { row("Durée", time(Int(info.frames))) }
                row("Zone lue par le moteur", impulse.length > 0 ? "\(time(impulse.offset)) → +\(time(impulse.length))" : "\(time(impulse.offset)) → " + String(localized: "fin du fichier"))
            }
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 4) {
                if let analysis {
                    row("Crête", (analysis.peakDB.isFinite ? analysis.peakDB.formatted(.number.precision(.fractionLength(1))) : "−∞") + " dB")
                    row("Début de l'attaque (−60 dB)", time(analysis.attackFrame), legend: .green)
                    row("Fin utile (−90 dB)", time(analysis.tailFrame), legend: .orange)
                }
            }
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 4) {
                if let analysis {
                    row("Silence au début", time(analysis.leadingFrames))
                    row("Silence à la fin", time(analysis.trailingFrames))
                }
            }
            Spacer(minLength: 0)
        }
        .font(.callout)
    }

    private func row(_ title: LocalizedStringKey, _ value: String, legend: Color? = nil) -> some View {
        GridRow {
            HStack(spacing: 6) {
                if let legend { Rectangle().fill(legend).frame(width: 3, height: 12) }
                Text(title).foregroundStyle(.secondary)
            }
            Text(verbatim: value).monospacedDigit().textSelection(.enabled)
        }
    }

    // MARK: Loading

    private func load() async {
        data = nil; pyramid = nil; response = nil; analysis = nil; failed = false
        guard let resolved else { return }
        let path = resolved.path, channel = resolved.channel, catalog = model.catalog
        info = catalog.info(at: path)
        let loaded = await Task.detached(priority: .userInitiated) { () -> (CurveData, PeakPyramid)? in
            guard let curve = try? CurveData.load(url: URL(fileURLWithPath: path), channel: channel) else { return nil }
            return (curve, PeakPyramid(samples: curve.samples))
        }.value
        data = loaded?.0
        pyramid = loaded?.1
        failed = loaded == nil
        if let count = loaded?.0.count { time = PlotViewport.signal(count: count, amplitude: yScales[.time] ?? .linear) }
        let all = await Task.detached(priority: .utility) { catalog.analysis(at: path) }.value
        analysis = all.flatMap { $0.indices.contains(channel - 1) ? $0[channel - 1] : nil }
    }

    /// The frequency response of the part the engine reads: again when the zone changes.
    private func computeResponse() async {
        guard let data, let range = used else { return }
        let computed = await Task.detached(priority: .userInitiated) {
            FrequencyResponse(samples: data.samples, range: range, sampleRate: data.sampleRate)
        }.value
        guard !Task.isCancelled else { return }
        // The frequency axis is logarithmic to begin with; once the person has chosen a scale it stays.
        let first = response == nil
        response = computed
        series = PlotSeriesSet(count: 1, accent: accent, names: [String(localized: "voie") + " \(resolved?.channel ?? 1)"])
        controller.series = series
        let scale: AxisScale = first ? .logarithmic : spectrum.x.scale
        spectrum = PlotViewport.curves(magnitudeCurves, xScale: scale, yScale: yScales[.spectrum] ?? .decibels(floor: -120),
                                       visibleX: scale == .logarithmic ? 20...20_000 : nil)
        // The vertical axis fits what is drawn: the group delay, in milliseconds, when that is what the inspector asks for.
        let drawn = controller.display.showGroupDelay ? phaseCurves.map { $0.groupDelay() } : phaseCurves
        phase = PlotViewport.curves(drawn, xScale: scale, visibleX: scale == .logarithmic ? 20...20_000 : nil)
    }
}
