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
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismissWindow) private var dismissWindow

    private enum Kind: String { case time, spectrum, phase }
    /// The width of the inspector: fixed, as in Keynote.
    private static let inspectorWidth: CGFloat = 280

    @State private var kind: Kind = .time
    @State private var data: CurveData?
    @State private var pyramid: PeakPyramid?
    @State private var response: FrequencyResponse?
    @State private var failed = false
    @State private var analysis: ImpulseAnalysis?
    @State private var info: SoundFileInfo?
    /// The zone the engine reads, in frames, as the handles show it: it follows the pointer, and the file when the drag ends.
    @State private var zone: ClosedRange<Double> = 0...1
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

    /// The colour of the zone the engine reads, wherever it is shown (the dotted edges and the sliders under the waveform, the bands of the two
    /// minimaps): its own, not the accent, which the curves have.
    private static let zoneColor = Color(white: 0.66)
    /// In a light appearance, where a white line would not show.
    private static let zoneColorLight = Color(white: 0.27)

    /// The zone as the handles show it now, in frames (it follows the pointer while a handle is dragged): what the spectrum is computed on.
    private var draftUsed: Range<Int>? {
        guard let total = data?.count, total > 1 else { return nil }
        let start = max(0, Int(zone.lowerBound.rounded())), end = Int(zone.upperBound.rounded())
        return start..<(end >= total - 1 ? total : max(end, start + 1))
    }

    /// The part of the file the engine reads, in frames.
    private var used: Range<Int>? {
        guard let impulse, let total = data?.count else { return nil }
        let start = min(impulse.offset, total)
        let end = impulse.length > 0 ? min(impulse.offset + impulse.length, total) : total
        return start..<max(end, start)
    }

    /// The zone of the impulse response, for the handles: from the first frame read to the last (the end of the file when it is read to
    /// the end).
    private var zoneOfImpulse: ClosedRange<Double> {
        guard let used, let total = data?.count, total > 1 else { return 0...1 }
        let last = Double(total - 1)
        let low = min(Double(used.lowerBound), last - 1)
        return low...max(min(Double(used.upperBound), last), low + 1)
    }

    /// Sets the zone of the impulse response from the handles (one change in the history of the matrix).
    private func commitZone(_ z: ClosedRange<Double>? = nil) {
        guard let target = model.detail, let impulse, let total = data?.count, total > 1 else { return }
        let zone = z ?? self.zone
        let start = max(0, Int(zone.lowerBound.rounded())), end = Int(zone.upperBound.rounded())
        var changed = impulse
        changed.offset = start
        // To the end of the file is a length of 0, as the configuration files say it.
        changed.length = ImpulseZone.length(start: start, end: end, total: total)
        model.edit(String(localized: "troncature d'une RI")) { $0.replace(changed, at: target.index, of: target.pair) }
        self.zone = zoneOfImpulse
        // It is a change of the configuration, not of the plot: where it is written is shown, if the inspector was closed.
        if !controller.showsInspector {
            controller.inspectorTab = "zone"
            controller.showsInspector = true
        }
    }

    /// A zone typed in the inspector, or set from the analysis: kept inside the file and at least one frame long.
    private func applyZone(start: Int, end: Int) {
        guard let total = data?.count, total > 1 else { return }
        let (s, e) = ImpulseZone.clamped(start: start, end: end, total: total)
        zone = Double(s)...Double(e)
        commitZone()
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
            PlotInspector(controller: controller, labels: .localized, accent: accent, extraTabs: [zoneTab])
                .inspectorColumnWidth(min: Self.inspectorWidth, ideal: Self.inspectorWidth, max: Self.inspectorWidth)
                // The help and the button of the inspector belong to its side of the toolbar: they stay at its left edge, and push the tools that
                // are before them.
                .toolbar { PlotInspectorToolbarContent(controller: controller, labels: .localized) }
        }
        .navigationTitle(String(localized: "Détail de la RI"))
        .navigationSubtitle(resolved.map { ($0.path as NSString).lastPathComponent } ?? "")
        .toolbar { PlotToolbarContent(controller: controller, labels: .localized, accent: accent, includesInspectorControls: false) }
        // The system lays the toolbar out once, and does not do it again when the inspector opens or closes: it is asked to, by a change of the
        // size of the window that nobody sees.
        .background(ToolbarRelayout(trigger: controller.showsInspector))
        .task(id: loadKey) { await load() }
        .task(id: ResponseKey(load: loadKey, used: draftUsed)) { await computeResponse() }
        .onChange(of: controller.yScale) { _, new in if kind != .phase { yScales[kind] = new } }
        // The handles follow the impulse response: when it is loaded, and when the zone changes elsewhere (the history, a table).
        .onChange(of: used) { _, _ in zone = zoneOfImpulse }
        .onChange(of: data?.count) { _, _ in zone = zoneOfImpulse }
        .onAppear {
            // A window with nothing to show (the system brought it back) closes at once.
            if model.detail == nil { dismissWindow(id: "impulse-detail"); return }
            controller.hasInspector = true
            controller.series = series
            #if DEBUG
            let env = ProcessInfo.processInfo.environment
            if let v = env["JACKCONVOLVER_DETAIL"].flatMap(Kind.init(rawValue:)) { kind = v }
            if !(env["JACKCONVOLVER_INSPECTOR"] ?? "").isEmpty { controller.showsInspector = true }
            if let tab = env["JACKCONVOLVER_INSPECTOR_TAB"], !tab.isEmpty { controller.inspectorTab = tab }
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
                VStack(spacing: 8) {
                    SignalPlot(signal: pyramid, viewport: $time, sampleRate: data.sampleRate, amplitude: yScales[.time] ?? .linear, accent: accent,
                               labels: .localized, controller: controller, annotations: annotations, region: regionEditor(total: data.count))
                    PlotOverview(signal: pyramid, viewport: $time, region: zone, regionColor: colorScheme == .dark ? Self.zoneColor : Self.zoneColorLight, accent: accent)
                }
            case .spectrum:
                if response != nil {
                    VStack(spacing: 8) {
                        CurvePlot(curves: magnitudeCurves, viewport: $spectrum, xUnit: "Hz", yScale: yScales[.spectrum] ?? .decibels(floor: -120),
                                  accent: accent, labels: .localized, controller: controller)
                        // The zone the spectrum is computed on: it changes with the ends, and the spectrum follows.
                        PlotZoneBar(signal: pyramid, zone: regionEditor(total: data.count), accent: accent)
                    }
                } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            case .phase:
                if response != nil {
                    VStack(spacing: 8) {
                        CurvePlot(curves: phaseCurves, viewport: $phase, xUnit: "Hz", yUnit: "°", accent: accent, labels: .localized,
                                  controller: controller, yScaleSwitchable: false)
                        PlotZoneBar(signal: pyramid, zone: regionEditor(total: data.count), accent: accent)
                    }
                } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            }
        }
    }

    /// The attack and the end of the tail are marked (the zone the engine reads has its own handles).
    private var annotations: PlotAnnotations {
        var a = PlotAnnotations()
        if let analysis {
            a.markers = [PlotMarker(id: "attack", x: Double(analysis.attackFrame), name: String(localized: "attaque"), color: .green),
                         PlotMarker(id: "tail", x: Double(analysis.tailFrame), name: String(localized: "fin utile"), color: .orange)]
        }
        return a
    }

    private func regionEditor(total: Int) -> PlotRegionEditor {
        let rate = data?.sampleRate ?? 0
        // The bubbles of a drag: the sample number (what the configuration file says) and the time it makes.
        let format: @Sendable (Double) -> String = { value in
            let frames = Int(value.rounded())
            guard rate > 0 else { return "\(frames)" }
            return "\(frames) · " + (Double(frames) / rate * 1000).formatted(.number.precision(.fractionLength(1))) + " ms"
        }
        var preview: PlotRegionPart?
        #if DEBUG
        preview = ProcessInfo.processInfo.environment["JACKCONVOLVER_ZONE_DRAG"].flatMap { ["start": .start, "end": .end, "move": .move][$0] }
        #endif
        return PlotRegionEditor(range: $zone,
                                style: PlotRegionStyle(color: Self.zoneColor, minLength: 1, bounds: 0...Double(max(total - 1, 1)), name: String(localized: "troncature de la RI"), format: format, lightColor: Self.zoneColorLight),
                                previewDragging: preview, onCommit: { commitZone() })
    }

    /// The page "Zone" of the inspector.
    private var zoneTab: PlotInspectorTab {
        PlotInspectorTab(id: "zone", title: String(localized: "Troncature")) {
            ZoneInspector(zone: zone, total: data?.count ?? 0, sampleRate: data?.sampleRate ?? 0,
                          attack: analysis?.attackFrame, tail: analysis?.tailFrame, apply: { applyZone(start: $0, end: $1) })
        }
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
        let columns = Group {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 4) {
                if let info { row("Durée", time(Int(info.frames))) }
                row("Troncature (.conf)", impulse.length > 0 ? "\(time(impulse.offset)) → +\(time(impulse.length))" : "\(time(impulse.offset)) → " + String(localized: "fin du fichier"))
            }
            .fixedSize(horizontal: true, vertical: false)
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 4) {
                if let analysis {
                    row("Crête", (analysis.peakDB.isFinite ? analysis.peakDB.formatted(.number.precision(.fractionLength(1))) : "−∞") + " dB")
                    row("Début de l'attaque (−60 dB)", time(analysis.attackFrame), legend: .green)
                    row("Fin utile (−90 dB)", time(analysis.tailFrame), legend: .orange)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 4) {
                if let analysis {
                    row("Silence au début", time(analysis.leadingFrames))
                    row("Silence à la fin", time(analysis.trailingFrames))
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 28) { columns; Spacer(minLength: 0) }
            VStack(alignment: .leading, spacing: 8) { columns }
        }
        .font(.callout)
    }

    private func row(_ title: LocalizedStringKey, _ value: String, legend: Color? = nil) -> some View {
        GridRow {
            HStack(spacing: 6) {
                if let legend { Rectangle().fill(legend).frame(width: 3, height: 12) }
                Text(title).foregroundStyle(.secondary).fixedSize(horizontal: true, vertical: false)
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
        let loaded = await ImpulseLoading.load(path: path, channel: channel)
        data = loaded?.0
        pyramid = loaded?.1
        failed = loaded == nil
        if let count = loaded?.0.count { time = PlotViewport.signal(count: count, amplitude: yScales[.time] ?? .linear) }
        #if DEBUG
        // JACKCONVOLVER_ZOOM=<first>,<last> shows that part of the waveform (to look at the minimap).
        if let z = ProcessInfo.processInfo.environment["JACKCONVOLVER_ZOOM"]?.split(separator: ",").compactMap({ Double($0) }), z.count == 2 {
            time.x = time.x.showing(z[0]...z[1])
        }
        #endif
        let all = await Task.detached(priority: .utility) { catalog.analysis(at: path) }.value
        analysis = all.flatMap { $0.indices.contains(channel - 1) ? $0[channel - 1] : nil }
    }

    /// The frequency response of the part the engine reads: again when the zone changes.
    private func computeResponse() async {
        guard let data, let range = draftUsed, range.count >= 2 else { return }
        // While a handle is dragged the zone changes at every movement: what was asked before the last one is dropped, and the transform waits
        // a moment to see whether another is coming.
        try? await Task.sleep(for: .milliseconds(25))
        guard !Task.isCancelled else { return }
        let computed = await Task.detached(priority: .userInitiated) {
            FrequencyResponse(samples: data.samples, range: range, sampleRate: data.sampleRate)
        }.value
        guard !Task.isCancelled else { return }
        // The first time the plots are fitted to the response; after that the person's zoom and scales stay as they are while the zone changes.
        let first = response?.isEmpty ?? true
        response = computed
        guard first else { return }
        series = PlotSeriesSet(count: 1, accent: accent, names: [String(localized: "voie") + " \(resolved?.channel ?? 1)"])
        controller.series = series
        let scale: AxisScale = .logarithmic
        spectrum = PlotViewport.curves(magnitudeCurves, xScale: scale, yScale: yScales[.spectrum] ?? .decibels(floor: -120),
                                       visibleX: scale == .logarithmic ? 20...20_000 : nil)
        // The vertical axis fits what is drawn: the group delay, in milliseconds, when that is what the inspector asks for.
        let drawn = controller.display.showGroupDelay ? phaseCurves.map { $0.groupDelay() } : phaseCurves
        phase = PlotViewport.curves(drawn, xScale: scale, visibleX: scale == .logarithmic ? 20...20_000 : nil)
    }
}
