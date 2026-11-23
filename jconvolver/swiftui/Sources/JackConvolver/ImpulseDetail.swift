// SPDX-License-Identifier: GPL-3.0-or-later

import AppearanceKit
import JConvolverKit
import PlotKit
import SoundFileKit
import SwiftUI

/// Which impulse response its page shows: the one at this place of this pair.
struct DetailTarget: Identifiable, Equatable {
    let pair: ConvPair
    let index: Int
    var id: String { "\(pair.input)-\(pair.output)-\(index)" }
}

/// The detail of an impulse response that comes from a sound file, in a page of the window: the waveform with the part the engine
/// reads and what the analysis found (where the attack starts, where the useful tail ends), the frequency response and the phase or
/// the group delay, drawn by PlotKit with the tools of its toolbar and an inspector for how the curves are shown.
struct ImpulseDetailPage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.appAccentColor) private var accent
    @Environment(\.colorScheme) private var colorScheme

    private enum Kind: String { case time, spectrum, phase }
    /// The width of the inspector: fixed, as in Keynote.
    private static let inspectorWidth: CGFloat = 280
    /// From this width of the page the inspector keeps its room beside the plot; under it, it floats over the plot instead of squeezing it.
    private static let dockedFrom: CGFloat = 1050
    /// Whether the page is wide enough for the docked inspector. It has a margin of its own when it goes back,
    /// so that it cannot flip at the limit.
    @State private var isWide = true
    /// The size of the page, and where the plot area ends in it: a floating inspector stops there, so that the sliders of the zone and the minimap
    /// under the plot stay within reach.
    @State private var pageHeight: CGFloat = 0
    @State private var plotBottom: CGFloat = 0
    /// Where a floating inspector starts in the page: under the tabs of the views, which are under the title and the legend.
    @State private var plotTop: CGFloat = 0
    private static let pageSpace = "impulsePage"

    @State private var kind: Kind = .time
    @State private var data: CurveData?
    @State private var pyramid: PeakPyramid?
    @State private var response: FrequencyResponse?
    @State private var failed = false
    @State private var analysis: ImpulseAnalysis?
    @State private var info: SoundFileInfo?
    /// The zone the engine reads, in frames, as the handles show it: it follows the pointer, and the file when the drag ends.
    @State private var zone: ClosedRange<Double> = 0...1
    private var controller: PlotController { model.plotController }
    @State private var series = PlotSeriesSet(count: 0)
    /// The trace each channel of `series` stands for (the channels keep their colour when the traces change).
    @State private var seriesKeys: [String] = []
    /// The traces other than the edited one: their samples, their peaks and their frequency response on the zone they read.
    @State private var others: [String: LoadedTrace] = [:]
    /// The references (the original of a file that was converted), loaded: their samples and their frequency response on the part that was read.
    @State private var refs: [String: LoadedTrace] = [:]
    /// The files already read, by path and channel, so that a trace whose zone changes is not read again.
    @State private var fileCache: [String: (CurveData, PeakPyramid)] = [:]
    /// Whether the traces are drawn with the zone, the gain and the delay of their place applied, instead of as the files are, and those traces.
    @State private var engineView = false
    /// Whether the difference of the two spectra is drawn when a comparison is looked at.
    @State private var showsDifference = false
    /// The vertical axes are to be fitted when the traces of the engine are made (the switch to "Appliquer troncature, gain et retard").
    @State private var fitsAfterEngine = false
    @State private var engineTraces: [String: LoadedTrace] = [:]
    @State private var engineEntries: [String: EngineEntry] = [:]
    @State private var time = PlotViewport.signal(count: 2)
    @State private var spectrum = PlotViewport.signal(count: 2)
    @State private var phase = PlotViewport.signal(count: 2)
    /// How the vertical axis is drawn in each view: kept when one goes from a view to another.
    @State private var yScales: [Kind: AmplitudeScale] = [.time: .linear, .spectrum: .decibels(floor: -120), .phase: .linear]

    /// A trace other than the edited one, loaded.
    struct LoadedTrace {
        var key: OtherKey
        var data: CurveData
        var pyramid: PeakPyramid
        var response: FrequencyResponse?
    }

    /// What an engine trace is made of: the file, and the zone, gain and delay of the place of the matrix.
    struct EngineEntry: Hashable { var id: String; var path: String; var channel: Int; var offset: Int; var length: Int; var gain: Double; var delay: Int }

    private struct EngineTaskKey: Hashable { var entries: [EngineEntry]; var cached: [String] }

    /// What decides whether a trace other than the edited one has to be loaded again: the file and the zone.
    struct OtherKey: Hashable { var id: String; var path: String; var channel: Int; var offset: Int; var length: Int }

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
        guard !model.isLocked, !isComparing else { self.zone = zoneOfImpulse; return }
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
                    // The part that the inspector shares the room of: the plot with what is under it. The figures below have the whole width, so
                    // the panel, docked or floating, never takes room from them.
                    VStack(alignment: .leading, spacing: 10) {
                        // With several traces, what each colour is, beside the title and without the inspector.
                        HStack(alignment: .top, spacing: 16) {
                            header(resolved, target).layoutPriority(1)
                            let differenceShown = showsDifference && kind == .spectrum && isComparing
                            if series.items.count > 1 || differenceShown {
                                TracesLegend(series: series, comparing: isComparing, differenceShown: differenceShown,
                                             onHideDifference: { showsDifference = false }).frame(maxWidth: .infinity)
                            }
                        }
                        rateBanner
                        conversionBanner
                        if let line = deviationLine {
                            HStack(spacing: 10) {
                                Label(line, systemImage: "chart.xyaxis.line").font(.callout).foregroundStyle(.secondary).lineLimit(2)
                                Spacer(minLength: 8)
                                // The curve of this difference, on the spectra, is one click away from the sentence.
                                // The difference is a curve of the spectra: showing it goes to the view of the frequency, from the other two.
                                let visible = showsDifference && kind == .spectrum
                                Button(visible ? "Masquer le spectre du résidu" : "Afficher le spectre du résidu") {
                                    if visible { showsDifference = false } else { showsDifference = true; kind = .spectrum }
                                }
                                    .controlSize(.small)
                                    .help("Le résidu : la différence des deux spectres, par douzièmes d'octave, dans la vue Fréquence")
                            }
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                        tabs(impulse)
                    }
                    .padding([.top, .horizontal], 14)
                    .coordinateSpace(name: Self.pageSpace)
                    // The inspector is a panel of glass: beside the plot when the page has the room, over it when it has not.
                    .plotOverlayInspector(isPresented: controller.showsInspector, docked: isWide, width: Self.inspectorWidth,
                                          bottomInset: plotBottom > 0 ? pageHeight - plotBottom : 0,
                                          topInset: plotTop > 0 ? plotTop : nil, trailingInset: 14,
                                          onOutsideClick: { controller.showsInspector = false }) {
                        PlotInspector(controller: controller, labels: .localized, accent: accent, extraTabs: [zoneTab], leadingTabs: [tracesTab])
                    }
                    // The width of the page decides whether the inspector keeps its room beside the plot or floats over it.
                    .onGeometryChange(for: CGSize.self, of: { $0.size }) { size in
                        // A page that is hidden has no size: it keeps what it had.
                        guard size.width > 100, size.height > 100 else { return }
                        pageHeight = size.height
                        let width = size.width
                        let wide = isWide ? width >= Self.dockedFrom - 24 : width >= Self.dockedFrom
                        if wide != isWide { isWide = wide }
                    }
                    facts(impulse).padding([.horizontal, .bottom], 14)
                }
            } else {
                TracesEmptyView()
            }
        }
        .task(id: loadKey) { await load() }
        .task(id: othersKey) { await loadOthers() }
        .task(id: EngineTaskKey(entries: engineView ? engineEntriesNow : [], cached: engineView ? fileCache.keys.sorted() : [])) { await computeEngine() }
        // The time axis follows the longest trace that is shown.
        .task(id: TimeFit(length: timeLength, load: loadKey)) { fitTime() }
        .onChange(of: model.traces) { _, _ in syncSeries() }
        .onChange(of: model.references) { _, _ in syncSeries() }
        .onChange(of: model.pendingConversion) { _, _ in syncSeries() }
        // The residual is far below the spectra: showing it or hiding it fits the vertical axis again to what is drawn, so that the spectra
        // keep the whole height when it is not there.
        .onChange(of: showsDifference) { _, _ in
            guard response?.isEmpty == false else { return }
            fitFrequencyAxes()
        }
        // The signal as the engine reads it has another level, another length, another delay: the vertical axes of the spectrum and of the phase
        // are fitted again to it, and to the file again when it is left. The traces of the engine are made a moment after the switch.
        .onChange(of: engineView) { _, on in
            if on { fitsAfterEngine = true } else { fitFrequencyAxes(); fitTimeAmplitude(force: true) }
        }
        .task(id: model.references) { await loadReferences() }
        // What is edited is always a trace that is shown: when the edited one is hidden (alone-view of another, the eye of the list), the edition goes to
        // the first one that is.
        .onChange(of: series.visible.map(\.id)) { _, shown in
            // With the gain applied the vertical axes follow what is drawn, so showing or hiding a trace fits them again.
            if engineView { fitFrequencyAxes(); fitTimeAmplitude(force: true) }
            guard let edited = editedIndex, !shown.contains(edited), let first = shown.first, model.traces.indices.contains(first) else { return }
            model.detail = model.traces[first]
        }
        .task(id: ResponseKey(load: loadKey, used: draftUsed)) { await computeResponse() }
        .onChange(of: controller.yScale) { _, new in if kind != .phase { yScales[kind] = new } }
        // The handles follow the impulse response: when it is loaded, and when the zone changes elsewhere (the history, a table).
        .onChange(of: used) { _, _ in zone = zoneOfImpulse }
        .onChange(of: data?.count) { _, _ in zone = zoneOfImpulse }
        .onAppear {
            controller.hasInspector = true
            // The traces have a page of their own in the inspector: the list of channels of the plot would say the same twice.
            controller.series = nil
            syncSeries()
            #if DEBUG
            let env = ProcessInfo.processInfo.environment
            if let v = env["JACKCONVOLVER_DETAIL"].flatMap(Kind.init(rawValue:)) { kind = v }
            if !(env["JACKCONVOLVER_INSPECTOR"] ?? "").isEmpty { controller.showsInspector = true }
            if let tab = env["JACKCONVOLVER_INSPECTOR_TAB"], !tab.isEmpty { controller.inspectorTab = tab }
            if !(env["JACKCONVOLVER_GROUPDELAY"] ?? "").isEmpty { controller.display.showGroupDelay = true }
            if let d = Int(env["JACKCONVOLVER_SMOOTH"] ?? ""), let s = OctaveSmoothing(rawValue: d) { controller.display.smoothing = s }
            #endif
        }
    }

    /// The response that is edited, with a menu that changes which one when there are several, and the button that adds one.
    @ViewBuilder private func editedTitle(_ resolved: (path: String, channel: Int)) -> some View {
        let title = Text(verbatim: "\((resolved.path as NSString).lastPathComponent) · \(String(localized: "voie")) \(resolved.channel)").font(.headline)
        HStack(spacing: 6) {
            if model.traces.count > 1 {
                Menu {
                    ForEach(Array(model.traces.enumerated()), id: \.element.id) { index, trace in
                        Button(model.traceFullName(trace) + " · " + model.traceDetail(trace)) { model.detail = trace }
                            .disabled(series.items.first { $0.id == index }?.isVisible == false)
                    }
                } label: {
                    HStack(spacing: 4) { title; Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary) }
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help(String(localized: "Trace éditée : changer"))
            } else {
                title
            }
            // Always there, whatever the inspector shows, and said in words: one more response on the plots, or the end of the analysis.
            AddTraceMenu { Label("Ajouter", systemImage: "plus") }
                .controlSize(.small)
                .help(String(localized: "Ajouter une réponse impulsionnelle aux tracés"))
            // While a conversion is looked at, the way out is the banner (keep it, or refuse it): a second one would not say which.
            if model.pendingConversion == nil {
                Button { model.closeAnalysis() } label: { Label("Fermer l'analyse", systemImage: "xmark") }
                    .controlSize(.small)
                    .help(String(localized: "Ne plus rien tracer et revenir à la page d'où l'analyse a été ouverte"))
            }
        }
    }

    /// A conversion that is looked at against its original: it is kept, or refused (the matrix goes back to the original).
    @ViewBuilder private var conversionBanner: some View {
        if let pending = model.pendingConversion {
            HStack(spacing: 10) {
                Label("Conversion à \(pending.rate.formatted(.number.precision(.fractionLength(0...1)))) Hz : à comparer avec l'original.", systemImage: "arrow.triangle.2.circlepath")
                    .font(.callout).lineLimit(2)
                Spacer(minLength: 8)
                Button("Refuser") { model.refuseConversion() }.controlSize(.small)
                    .help(pending.created ? "Revient à l'original dans la matrice et met le fichier converti à la corbeille." : "Revient à l'original dans la matrice.")
                Button("Garder la conversion") { model.keepConversion() }.controlSize(.small).buttonStyle(.borderedProminent).accentTint()
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
    }

    /// A file at another rate than the one that is expected: said, with the way to bring it to it.
    @ViewBuilder private var rateBanner: some View {
        if let expected = model.expectedRate, let rate = data?.sampleRate, abs(rate - expected) > 0.5, let path = resolved?.path {
            let hz: (Double) -> String = { $0.formatted(.number.precision(.fractionLength(0...1))) }
            HStack(spacing: 10) {
                Label(model.mode == .realTime ? "Ce fichier est à \(hz(rate)) Hz, le serveur JACK à \(hz(expected)) Hz."
                                              : "Ce fichier est à \(hz(rate)) Hz, le fichier d'entrée à \(hz(expected)) Hz.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange).lineLimit(2)
                Spacer(minLength: 8)
                ConvertButton(path: path, rate: expected)
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
    }

    private func header(_ resolved: (path: String, channel: Int), _ target: DetailTarget) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            editedTitle(resolved)
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
    /// The three views, as tabs of equal width over the whole width of the container, a cell of glass each.
    private var kindStrip: some View {
        GlassTabs(selection: $kind, items: [(.time, String(localized: "Temps")), (.spectrum, String(localized: "Fréquence")), (.phase, String(localized: "Phase"))])
    }

    private func tabs(_ impulse: ConvImpulse) -> some View {
        VStack(spacing: 8) {
            kindStrip.padding(.top, 10).padding(.horizontal, 8)
                // A floating inspector starts under the tabs of the views, so that they can all be reached.
                .onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .named(Self.pageSpace)).maxY + 8 }) { plotTop = $0 }
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
                    // With the zone, the gain and the delay applied, the zone is not drawn on the file: no handles, no markers of the file.
                    SignalPlot(traces: timeTraces, viewport: $time, sampleRate: data.sampleRate, amplitude: yScales[.time] ?? .linear, accent: accent,
                               labels: .localized, controller: controller, annotations: engineView || isComparing ? PlotAnnotations() : annotations,
                               region: showsHandles ? regionEditor(total: data.count) : nil)
                        .trackPlotBottom(below: PlotLayout.bottom + (showsHandles ? PlotLayout.regionRail : 0), in: Self.pageSpace) { plotBottom = $0 }
                    PlotOverview(signal: engineView ? (editedEngine?.pyramid ?? pyramid) : pyramid, viewport: $time, region: engineView || isComparing ? nil : zone,
                                 regionColor: colorScheme == .dark ? Self.zoneColor : Self.zoneColorLight, accent: editedColor)
                }
            case .spectrum:
                if hasResponse {
                    VStack(spacing: 8) {
                        CurvePlot(curves: magnitudeCurves, viewport: $spectrum, xUnit: "Hz", yScale: yScales[.spectrum] ?? .decibels(floor: -120),
                                  accent: accent, labels: .localized, controller: controller)
                            .trackPlotBottom(below: PlotLayout.bottom, in: Self.pageSpace) { plotBottom = $0 }
                        // The zone the spectrum is computed on: it changes with the ends, and the spectrum follows.
                        if showsHandles { PlotZoneBar(signal: pyramid, zone: regionEditor(total: data.count), accent: editedColor) }
                    }
                } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            case .phase:
                if hasResponse {
                    VStack(spacing: 8) {
                        CurvePlot(curves: phaseCurves, viewport: $phase, xUnit: "Hz", yUnit: "°", accent: accent, labels: .localized,
                                  controller: controller, yScaleSwitchable: false)
                            .trackPlotBottom(below: PlotLayout.bottom, in: Self.pageSpace) { plotBottom = $0 }
                        if showsHandles { PlotZoneBar(signal: pyramid, zone: regionEditor(total: data.count), accent: editedColor) }
                    }
                } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            }
        }
    }

    /// The handles of the zone, its bar and its rail: only to change it, so not with the zone applied to the traces, nor while the engine runs.
    private var showsHandles: Bool { !engineView && !model.isLocked && !isComparing }

    /// A comparison with a reference is only looked at: no markers of the analysis, no handles, no zone to change.
    private var isComparing: Bool { !model.references.isEmpty }

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
            VStack(alignment: .leading, spacing: 8) {
                LockBanner().padding(.top, 8)
                if isComparing {
                    Label("Comparaison : consultation seulement. Fermez-la pour régler la troncature.", systemImage: "eye")
                        .font(.callout).foregroundStyle(.secondary).padding(.top, 8)
                }
                ZoneInspector(zone: zone, total: data?.count ?? 0, sampleRate: data?.sampleRate ?? 0,
                              attack: analysis?.attackFrame, tail: analysis?.tailFrame, apply: { applyZone(start: $0, end: $1) })
                    .disabled(model.isLocked || isComparing)
            }
        }
    }

    // MARK: The traces

    /// The place of the edited trace among the traces, which is the number of its channel in `series`.
    private var editedIndex: Int? { model.detail.flatMap { model.traces.firstIndex(of: $0) } }

    /// The channels that are shown, the edited one first (it is drawn on top), the others paler.
    private var drawOrder: [PlotSeries] {
        let shown = series.visible
        guard let e = editedIndex else { return shown }
        return shown.filter { $0.id == e } + shown.filter { $0.id != e }
    }

    /// The colour of the edited trace, which the minimaps are drawn in: they show the signal that is edited.
    private var editedColor: Color {
        editedIndex.flatMap { i in series.items.first { $0.id == i }?.color } ?? accent
    }

    private func tint(_ channel: PlotSeries) -> Color { channel.id == editedIndex ? channel.color : channel.color.opacity(0.55) }

    /// What the plots need of a trace: its samples, its peaks and its frequency response, when they are there.
    private func loadedTrace(_ id: Int) -> (data: CurveData, pyramid: PeakPyramid, response: FrequencyResponse?)? {
        // After the traces of the matrix come the references.
        if id >= model.traces.count {
            let index = id - model.traces.count
            guard model.references.indices.contains(index) else { return nil }
            return refs[model.references[index].id].map { ($0.data, $0.pyramid, $0.response) }
        }
        guard model.traces.indices.contains(id) else { return nil }
        let trace = model.traces[id]
        if engineView { return engineTraces[trace.id].map { ($0.data, $0.pyramid, $0.response) } }
        if trace == model.detail {
            guard let data, let pyramid else { return nil }
            return (data, pyramid, response)
        }
        return others[trace.id].map { ($0.data, $0.pyramid, $0.response) }
    }

    private var timeTraces: [PlotTrace] {
        // Each trace is placed by time: a response recorded at another rate than the edited one is spread over the axis of the edited one.
        let reference = data?.sampleRate ?? 0
        return drawOrder.compactMap { s in
            loadedTrace(s.id).map {
                PlotTrace(name: s.name, signal: $0.pyramid, color: tint(s), timeScale: reference > 0 && $0.data.sampleRate > 0 ? reference / $0.data.sampleRate : 1)
            }
        }
    }

    private var magnitudeCurves: [PlotCurve] {
        var curves: [PlotCurve] = drawOrder.compactMap { s in
            guard let r = loadedTrace(s.id)?.response else { return nil }
            return PlotCurve(name: s.name, x: r.frequencies, y: r.magnitudes, color: tint(s), isMagnitude: true)
        }
        // A comparison also draws the difference of the two spectra, under them: how far they are from each other.
        if showsDifference, let reference = model.references.first, let edited = response, !edited.isEmpty, let other = refs[reference.id]?.response, !other.isEmpty {
            let difference = SpectrumComparison.difference(edited, other)
            if !difference.frequencies.isEmpty {
                curves.append(PlotCurve(name: String(localized: "résidu"), x: difference.frequencies, y: difference.magnitudes, color: Color(white: 0.62),
                                        filled: false, isMagnitude: true))
            }
        }
        return curves
    }

    private var phaseCurves: [PlotCurve] {
        drawOrder.compactMap { s in
            guard let r = loadedTrace(s.id)?.response else { return nil }
            var curve = PlotCurve(name: s.name, x: r.frequencies, y: r.phases, color: tint(s), filled: false, phase: .degrees)
            curve.exactGroupDelay = r.groupDelays
            return curve
        }
    }

    /// The edited trace as the engine reads it.
    private var editedEngine: LoadedTrace? { model.detail.flatMap { engineTraces[$0.id] } }

    /// Whether what the spectrum and the phase need is there: the response of the edited file, or of the traces as the engine reads them.
    private var hasResponse: Bool { engineView ? (editedEngine?.response != nil) : response != nil }

    private var engineEntriesNow: [EngineEntry] {
        model.traces.compactMap { trace in
            guard let impulse = model.impulse(of: trace), case .file(let file, let channel) = impulse.source else { return nil }
            return EngineEntry(id: trace.id, path: ConvConfig.path(of: file, directory: impulse.directory, configDirectory: model.configDirectory),
                               channel: channel, offset: impulse.offset, length: impulse.length, gain: impulse.gain, delay: impulse.delay)
        }
    }

    /// Makes the traces as the engine reads them: the zone of the file, the gain, the delay, then their peaks and their frequency response.
    private func computeEngine() async {
        guard engineView else { return }
        let entries = engineEntriesNow
        var next: [String: LoadedTrace] = [:]
        var made: [String: EngineEntry] = [:]
        for entry in entries {
            if let known = engineTraces[entry.id], engineEntries[entry.id] == entry { next[entry.id] = known; made[entry.id] = entry; continue }
            guard let raw = fileCache["\(entry.path)#\(entry.channel)"]?.0 else { continue }
            let built = await Task.detached(priority: .userInitiated) { () -> (CurveData, PeakPyramid, FrequencyResponse?) in
                let samples = EngineSamples.make(raw.samples, offset: entry.offset, length: entry.length, gain: entry.gain, delay: entry.delay)
                let response = samples.count >= 2 ? FrequencyResponse(samples: samples, range: 0..<samples.count, sampleRate: raw.sampleRate) : nil
                return (CurveData(samples: samples, sampleRate: raw.sampleRate), PeakPyramid(samples: samples.isEmpty ? [0] : samples), response)
            }.value
            guard !Task.isCancelled else { return }
            next[entry.id] = LoadedTrace(key: OtherKey(id: entry.id, path: entry.path, channel: entry.channel, offset: entry.offset, length: entry.length),
                                         data: built.0, pyramid: built.1, response: built.2)
            made[entry.id] = entry
        }
        engineTraces = next
        engineEntries = made
        // The signal as the engine reads it: the vertical axes follow what is drawn, whatever was changed (the switch, a gain, a zone).
        fitsAfterEngine = false
        fitFrequencyAxes()
        fitTimeAmplitude(force: true)
    }

    /// The vertical axis of the waveform is not limited to the full scale: a signal with a gain above 1 is shown whole, and one with a gain of
    /// -15 dB is not drawn in a corner. The bounds follow the largest sample of the traces that are shown; for the file as it is, never less than
    /// the full scale (a quiet recording is seen as quiet), for the signal as the engine reads it (the gain applied), nothing more than it needs.
    /// The view is fitted to the bounds when it was, when they grew, or when `force` says so (the switch between the two). A scale in decibels
    /// keeps its range.
    private func fitTimeAmplitude(force: Bool = false) {
        guard yScales[.time] ?? .linear == .linear else { return }
        let peak = series.visible.compactMap { loadedTrace($0.id)?.data.samples.lazy.map { abs(Double($0)) }.max() }.max() ?? 0
        guard peak.isFinite else { return }
        let m = engineView ? peak * 1.05 : max(1.05, peak * 1.05)
        guard m > 0 else { return }
        let current = time.y.bounds.upperBound
        guard force || abs(current - m) > 1e-9 else { return }
        time.y = force || time.y.isFitted || m > current ? AxisState(bounds: -m...m, minSpan: 1e-9) : time.y.withBounds(-m...m)
    }

    /// Fits the vertical axes of the spectrum and of the phase to the curves that are drawn, the horizontal ones staying where the person put them.
    private func fitFrequencyAxes() {
        let scale: AxisScale = .logarithmic
        let fitted = PlotViewport.curves(magnitudeCurves, xScale: scale, yScale: yScales[.spectrum] ?? .decibels(floor: -120), visibleX: 20...20_000)
        spectrum = PlotViewport(x: spectrum.x, y: fitted.y)
        let drawn = controller.display.showGroupDelay ? phaseCurves.map { $0.groupDelay() } : phaseCurves
        if !drawn.isEmpty { phase = PlotViewport(x: phase.x, y: PlotViewport.curves(drawn, xScale: scale, visibleX: 20...20_000).y) }
    }

    /// The rows of the list of traces in the inspector.
    private var traceRows: [TraceRow] {
        let rate = data?.sampleRate
        var rows = model.traces.enumerated().map { i, trace in
            var note: String?
            if let rate, let other = loadedTrace(i)?.data.sampleRate, abs(other - rate) > 0.5 {
                note = String(localized: "\(Int(other)) Hz : placée sur l'axe du temps de la trace éditée.")
            }
            return TraceRow(id: i, target: trace, name: model.traceName(trace), detail: model.traceDetail(trace), note: note)
        }
        for (j, reference) in model.references.enumerated() {
            rows.append(TraceRow(id: model.traces.count + j, target: nil, referenceID: reference.id, name: reference.name,
                                 detail: (reference.path as NSString).lastPathComponent,
                                 note: String(localized: "Référence : pour comparer, en lecture seule.")))
        }
        return rows
    }

    /// The page "Tracés" of the inspector.
    private var tracesTab: PlotInspectorTab {
        PlotInspectorTab(id: "traces", title: String(localized: "Tracés")) { TracesInspector(series: series, rows: traceRows, engineView: $engineView, showsDifference: $showsDifference, isComparing: isComparing) }
    }

    /// Makes the channels of the plots follow the traces: one each, with the colour and the visibility it had.
    private func syncSeries() {
        let traces = model.traces, references = model.references
        let keys = traces.map(\.id) + references.map(\.id)
        let old = series.items, oldKeys = seriesKeys
        // While a conversion is compared with its original, the colours are named for what they are, not for the places of the matrix.
        let converted = model.pendingConversion.map { Self.kilohertz($0.rate) }
        let names = traces.map { trace -> String in
            guard let converted, !references.isEmpty, trace == model.detail else { return model.traceName(trace) }
            return String(localized: "Ré-échantillonné · \(converted) kHz")
        } + references.map(\.name)
        let next = PlotSeriesSet(count: keys.count, accent: accent, names: names)
        for (i, key) in keys.enumerated() {
            if let k = oldKeys.firstIndex(of: key), let item = old.first(where: { $0.id == k }) {
                next.items[i].color = item.color
                next.items[i].isVisible = item.isVisible
            }
        }
        series = next
        seriesKeys = keys
    }

    private static func kilohertz(_ rate: Double) -> String { (rate / 1000).formatted(.number.precision(.fractionLength(0...1))) }

    /// What decides whether the traces other than the edited one have to be loaded again.
    private var othersKey: [OtherKey] {
        model.traces.filter { $0 != model.detail }.compactMap { trace in
            guard let impulse = model.impulse(of: trace), case .file(let file, let channel) = impulse.source else { return nil }
            return OtherKey(id: trace.id, path: ConvConfig.path(of: file, directory: impulse.directory, configDirectory: model.configDirectory),
                            channel: channel, offset: impulse.offset, length: impulse.length)
        }
    }

    /// Reads the traces other than the edited one, and computes their frequency response on the zone each one reads.
    private func loadOthers() async {
        let keys = othersKey
        var next: [String: LoadedTrace] = [:]
        for key in keys {
            if let known = others[key.id], known.key == key { next[key.id] = known; continue }
            let fileKey = "\(key.path)#\(key.channel)"
            var file = fileCache[fileKey]
            if file == nil {
                file = await ImpulseLoading.load(path: key.path, channel: key.channel)
                fileCache[fileKey] = file
            }
            guard !Task.isCancelled else { return }
            guard let (curve, pyramid) = file else { continue }
            let total = curve.count
            let start = min(key.offset, total)
            let end = key.length > 0 ? min(key.offset + key.length, total) : total
            let range = start..<max(end, start)
            var computed: FrequencyResponse?
            if range.count >= 2 {
                computed = await Task.detached(priority: .userInitiated) { FrequencyResponse(samples: curve.samples, range: range, sampleRate: curve.sampleRate) }.value
            }
            guard !Task.isCancelled else { return }
            next[key.id] = LoadedTrace(key: key, data: curve, pyramid: pyramid, response: computed)
        }
        others = next
    }

    /// Reads the references and computes their frequency response on the part of the file that was read.
    private func loadReferences() async {
        var next: [String: LoadedTrace] = [:]
        for reference in model.references {
            let fileKey = "\(reference.path)#\(reference.channel)"
            var file = fileCache[fileKey]
            if file == nil {
                file = await ImpulseLoading.load(path: reference.path, channel: reference.channel)
                fileCache[fileKey] = file
            }
            guard !Task.isCancelled else { return }
            guard let (curve, pyramid) = file else { continue }
            let total = curve.count
            let start = min(reference.offset, total)
            let end = reference.length > 0 ? min(reference.offset + reference.length, total) : total
            let range = start..<max(end, start)
            var computed: FrequencyResponse?
            if range.count >= 2 {
                computed = await Task.detached(priority: .userInitiated) { FrequencyResponse(samples: curve.samples, range: range, sampleRate: curve.sampleRate) }.value
            }
            guard !Task.isCancelled else { return }
            next[reference.id] = LoadedTrace(key: OtherKey(id: reference.id, path: reference.path, channel: reference.channel, offset: reference.offset, length: reference.length),
                                             data: curve, pyramid: pyramid, response: computed)
        }
        refs = next
    }

    /// How far the response that is edited is from the first reference, over the band where both are known.
    private var deviationLine: String? {
        guard let reference = model.references.first, let edited = response, !edited.isEmpty, let other = refs[reference.id]?.response,
              let deviation = SpectrumComparison.maxDeviation(edited, other) else { return nil }
        let db = deviation.decibels.formatted(.number.precision(.fractionLength(2)))
        let upper = (deviation.band.upperBound / 1000).formatted(.number.precision(.fractionLength(1)))
        let at = (deviation.hertz < 1000 ? Int(deviation.hertz.rounded()).formatted() + " Hz" : (deviation.hertz / 1000).formatted(.number.precision(.fractionLength(1))) + " kHz")
        return String(localized: "Écart avec l'original : \(db) dB au plus (vers \(at)), de 20 Hz à \(upper) kHz, par douzièmes d'octave.")
    }

    /// The length of the time axis, in frames of the edited trace: the longest of the traces that are shown (hidden ones do not count, so that
    /// showing one alone fits the axis to it).
    private var timeLength: Int {
        let reference = data?.sampleRate ?? 0
        return series.visible.compactMap { channel -> Int? in
            guard let l = loadedTrace(channel.id) else { return nil }
            let scale = reference > 0 && l.data.sampleRate > 0 ? reference / l.data.sampleRate : 1
            return Int((Double(l.data.count) * scale).rounded(.up))
        }.max() ?? 0
    }

    private struct TimeFit: Hashable { var length: Int; var load: String }

    /// Fits the time axis to what is shown.
    private func fitTime() {
        let length = timeLength
        guard length >= 2 else { return }
        time = PlotViewport.signal(count: length, amplitude: yScales[.time] ?? .linear)
        fitTimeAmplitude()
        #if DEBUG
        // JACKCONVOLVER_ZOOM=<first>,<last> shows that part of the waveform (to look at the minimap).
        if let z = ProcessInfo.processInfo.environment["JACKCONVOLVER_ZOOM"]?.split(separator: ",").compactMap({ Double($0) }), z.count == 2 {
            time.x = time.x.showing(z[0]...z[1])
        }
        #endif
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
        if let loaded { fileCache["\(path)#\(channel)"] = loaded }
        data = loaded?.0
        pyramid = loaded?.1
        failed = loaded == nil
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
        let scale: AxisScale = .logarithmic
        spectrum = PlotViewport.curves(magnitudeCurves, xScale: scale, yScale: yScales[.spectrum] ?? .decibels(floor: -120),
                                       visibleX: scale == .logarithmic ? 20...20_000 : nil)
        // The vertical axis fits what is drawn: the group delay, in milliseconds, when that is what the inspector asks for.
        let drawn = controller.display.showGroupDelay ? phaseCurves.map { $0.groupDelay() } : phaseCurves
        phase = PlotViewport.curves(drawn, xScale: scale, visibleX: scale == .logarithmic ? 20...20_000 : nil)
    }
}

private extension View {
    /// Reports where the plot area of a plot ends, in a named coordinate space: the bottom of the view less what is under the plot area.
    func trackPlotBottom(below: CGFloat, in space: String, _ report: @escaping (CGFloat) -> Void) -> some View {
        onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .named(space)).maxY - below }) { report($0) }
    }
}
