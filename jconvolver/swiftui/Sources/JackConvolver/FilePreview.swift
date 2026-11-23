// SPDX-License-Identifier: GPL-3.0-or-later

import AppearanceKit
import JConvolverKit
import PlotKit
import SoundFileKit
import SwiftUI

/// A sound file of the list, looked at without being placed: the waveform, the frequency response and the phase of its channels, in a popover
/// that is not modal. It is the plot of the detail window without what edits the zone (no handles, no minimap, no inspector), whole file. A file
/// with several channels shows them together, in a colour each, and the legend shows or hides them.
struct FilePreview: View {
    @Environment(AppModel.self) private var model
    @Environment(\.appAccentColor) private var accent

    let path: String
    /// The channel (from 1) the person asked for, shown alone at first; `nil` for all the channels.
    let channel: Int?

    private enum Kind: String { case time, spectrum, phase }

    @State private var kind: Kind = .time
    @State private var datas: [CurveData] = []
    @State private var pyramids: [PeakPyramid] = []
    @State private var responses: [FrequencyResponse] = []
    @State private var failed = false
    @State private var series = PlotSeriesSet(count: 1)
    @State private var time = PlotViewport.signal(count: 2)
    @State private var spectrum = PlotViewport.signal(count: 2)
    @State private var phase = PlotViewport.signal(count: 2)
    /// How the phase is shown: unwrapped, without its delay, or as a group delay (the options of the inspector of the detail window).
    @State private var display = PlotDisplayOptions()

    private static let sidebarWidth: CGFloat = 250

    private var info: SoundFileInfo? { model.catalog.info(at: path) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            HStack(spacing: 10) {
                Group {
                    if !datas.isEmpty, pyramids.count == datas.count { plot } else if failed {
                        Text("Ce fichier ne peut pas être lu.").foregroundStyle(.red).frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .box()
                sidebar
            }
        }
        .padding(14)
        .frame(width: 700 + Self.sidebarWidth + 10, height: 460)
        .task(id: path) { await load() }
    }

    /// What is shown, as the inspector of a window says it: the visualisation first, then what belongs to that type (the options of the phase),
    /// then the channels.
    private var sidebar: some View {
        @Bindable var options = display
        let labels = PlotLabels.localized
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                section(String(localized: "Visualisation")) {
                    Picker("Visualisation", selection: $kind) {
                        Text("Temps").tag(Kind.time)
                        Text("Fréquence").tag(Kind.spectrum)
                        Text("Phase").tag(Kind.phase)
                    }
                    .labelsHidden().pickerStyle(.menu).frame(maxWidth: .infinity, alignment: .leading)
                }
                if kind == .phase {
                    // The group delay replaces the phase: the two other options are then of no use.
                    section(labels.phase) {
                        VStack(alignment: .leading, spacing: 8) {
                            option(labels.groupDelay, labels.groupDelayHelp, isOn: $options.showGroupDelay)
                            option(labels.unwrapPhase, labels.unwrapPhaseHelp, isOn: $options.unwrapPhase).disabled(options.showGroupDelay)
                            option(labels.removeDelay, labels.removeDelayHelp, isOn: $options.removeDelay).disabled(options.showGroupDelay)
                        }
                    }
                }
                // The spectrum, and the group delay, are smoothed over a fraction of an octave.
                if kind == .spectrum || (kind == .phase && options.showGroupDelay) {
                    section(labels.smoothing, info: labels.smoothingHelp) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(labels.smoothingBand).foregroundStyle(.secondary)
                                Spacer(minLength: 8)
                                Picker(labels.smoothingBand, selection: $options.smoothing) {
                                    ForEach(OctaveSmoothing.allCases, id: \.self) { Text($0 == .none ? labels.noSmoothing : $0.title).tag($0) }
                                }
                                .labelsHidden().pickerStyle(.menu).fixedSize()
                            }
                            .font(.callout)
                            option(labels.showUnsmoothed, nil, isOn: $options.showsUnsmoothed).disabled(options.smoothing == .none)
                        }
                    }
                }
                if datas.count > 1 {
                    // The channels, as the inspector of the detail window lists them: show or hide, colour, alone, order.
                    PlotChannelList(series: series, labels: labels, inInspector: true).padding(.top, 10)
                }
            }
            .padding(12)
        }
        .frame(width: Self.sidebarWidth).frame(maxHeight: .infinity)
        .box()
    }

    private func section<Content: View>(_ title: String, info: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 12.5, weight: .semibold))
                if let info { PlotInfoButton(text: info, label: PlotLabels.localized.moreDetails) }
            }
            content()
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func option(_ title: String, _ help: String?, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 4) {
            Toggle(title, isOn: isOn).toggleStyle(.checkbox).accentTint()
            if let help { PlotInfoButton(text: help, label: PlotLabels.localized.moreDetails) }
            Spacer(minLength: 0)
        }
        .font(.callout)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: (path as NSString).lastPathComponent).font(.headline).lineLimit(1).truncationMode(.middle)
            if let info {
                let seconds = info.sampleRate > 0 ? Double(info.frames) / info.sampleRate : 0
                Text(verbatim: "\(info.container) · \(info.encoding) · \(Int(info.sampleRate)) Hz · \(info.channels) " + String(localized: "voies")
                     + " · \(info.frames) " + String(localized: "éch.") + " (" + seconds.formatted(.number.precision(.fractionLength(2))) + " s)")
                    .font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    @ViewBuilder private var plot: some View {
        let rate = datas[0].sampleRate
        switch kind {
        case .time:
            SignalPlot(traces: series.traces { pyramids[$0] }, viewport: $time, sampleRate: rate, accent: accent, labels: .localized)
        case .spectrum:
            if responses.count == datas.count {
                CurvePlot(curves: magnitudeCurves, viewport: $spectrum, xUnit: "Hz", yScale: .decibels(floor: -120), accent: accent, labels: .localized, display: display)
            } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        case .phase:
            if responses.count == datas.count {
                CurvePlot(curves: phaseCurves, viewport: $phase, xUnit: "Hz", yUnit: "°", accent: accent, labels: .localized, display: display,
                          yScaleSwitchable: false)
            } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
    }

    private var magnitudeCurves: [PlotCurve] {
        series.curves({ i in (responses[i].frequencies, responses[i].magnitudes) }, isMagnitude: true)
    }

    private var phaseCurves: [PlotCurve] {
        series.curves({ i in (responses[i].frequencies, responses[i].phases) }, filled: false, phase: .degrees,
                      groupDelay: { i in responses[i].groupDelays })
    }

    /// Reads the channels, then computes their frequency responses (the whole file: there is no zone here), all channels at once.
    private func load() async {
        datas = []; pyramids = []; responses = []; failed = false
        let loaded = await ImpulseLoading.loadAll(path: path)
        guard !Task.isCancelled else { return }
        guard let loaded else { failed = true; return }
        let count = loaded.count
        series = PlotSeriesSet(count: count, accent: accent, names: (1...count).map { String(localized: "voie") + " \($0)" })
        // A channel asked for is shown alone; the legend brings the others.
        if let channel, count > 1, (1...count).contains(channel) { series.solo(channel - 1) }
        datas = loaded.map(\.0)
        pyramids = loaded.map(\.1)
        time = PlotViewport.signal(count: max(datas[0].count, 2))
        guard datas[0].count >= 2 else { return }
        let computed = await withTaskGroup(of: (Int, FrequencyResponse).self) { group in
            for (i, d) in datas.enumerated() {
                group.addTask(priority: .userInitiated) { (i, FrequencyResponse(samples: d.samples, range: 0..<d.count, sampleRate: d.sampleRate)) }
            }
            var out = [FrequencyResponse?](repeating: nil, count: datas.count)
            for await (i, r) in group { out[i] = r }
            return out.compactMap { $0 }
        }
        guard !Task.isCancelled, computed.count == count else { return }
        responses = computed
        spectrum = PlotViewport.curves(magnitudeCurves, xScale: .logarithmic, yScale: .decibels(floor: -120), visibleX: 20...20_000)
        phase = PlotViewport.curves(phaseCurves, xScale: .logarithmic, visibleX: 20...20_000)
    }
}

private extension View {
    /// The light container of the plot and of the list of channels.
    func box() -> some View {
        background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
    }
}
