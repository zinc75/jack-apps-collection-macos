// SPDX-License-Identifier: MIT

import Observation
import SwiftUI

/// How the body of a curve is filled: a gradient that fades, or a flat translucent colour. The fill is always there (it is what
/// shows the waveform between its envelope lines); only its style is a choice.
public enum PlotFill: Equatable, Sendable {
    /// A gradient, at this strength (1 is the full one).
    case gradient(Double)
    /// A flat colour at this opacity.
    case flat(Double)
    /// An opaque body, in the colour mixed with the background (1 is the colour itself): what is drawn over it hides what is under
    /// it, as the oscillations of a curve drawn over another would.
    case solid(Double)
}

/// The style of the fill: a gradient for one curve; for several an opaque body by default, so that the curve that is on top is the
/// one that is seen (gradients over each other fight).
public struct PlotGradient: Equatable, Sendable {
    /// A gradient when one curve is shown (a flat fill when it is off).
    public var enabled = true
    /// And also when several are shown (the one on top still hides the ones under it).
    public var withSeveral = false

    public init(enabled: Bool = true, withSeveral: Bool = false) {
        self.enabled = enabled
        self.withSeveral = withSeveral
    }

    /// The fill for a number of curves.
    public func fill(curves count: Int) -> PlotFill {
        if count <= 1 { return enabled ? .gradient(1) : .flat(0.34) }
        return enabled && withSeveral ? .gradient(0.7) : .solid(0.5)
    }
}

/// The settings of how a plot looks, the ones that are not worth a button of the toolbar: they live in the inspector of the
/// window, as the format settings of an editor do. More come here with time.
@MainActor
@Observable
public final class PlotDisplayOptions {
    public var gradient = PlotGradient()
    /// A phase is drawn unwrapped (continuous) instead of between −180° and +180°.
    public var unwrapPhase = false
    /// The delay is taken out of a phase (the straight line it makes).
    public var removeDelay = false
    /// A phase is shown as its group delay (the slope of the unwrapped phase, in ms).
    public var showGroupDelay = false
    /// The magnitudes are smoothed over a fraction of an octave, and the raw spectrum stays behind, thin and pale.
    public var smoothing = OctaveSmoothing.none
    public var showsUnsmoothed = true
    public init() {}
}

/// A page of the inspector that the application adds to the ones of the plot (the zone of a signal, say): a tab at the top of the
/// inspector, and what is shown when it is chosen. Build the page from `PlotInspectorSection`s.
public struct PlotInspectorTab: Identifiable {
    public let id: String
    public var title: String
    let content: AnyView

    public init<Content: View>(id: String, title: String, @ViewBuilder content: () -> Content) {
        self.id = id
        self.title = title
        self.content = AnyView(content())
    }
}

/// A section of a page of the inspector, as in the inspectors of the editors of the system: a title with a chevron that folds it, and
/// optionally a box in the title that switches on what the section sets. Whether it is folded is kept by the plot, so that it stays
/// as it was when the person goes from one page to another.
public struct PlotInspectorSection<Content: View>: View {
    @Environment(PlotController.self) private var controller
    let id: String
    let title: String
    let isOn: Binding<Bool>?
    let info: String?
    let hasContent: Bool
    let content: Content

    /// - Parameter info: the long explanation of the section, in a popover from an "i" next to its title.
    public init(id: String, title: String, isOn: Binding<Bool>? = nil, info: String? = nil, @ViewBuilder content: () -> Content) {
        self.id = id
        self.title = title
        self.isOn = isOn
        self.info = info
        self.hasContent = true
        self.content = content()
    }

    fileprivate init(id: String, title: String, isOn: Binding<Bool>?, info: String?, empty: Content) {
        self.id = id
        self.title = title
        self.isOn = isOn
        self.info = info
        self.hasContent = false
        self.content = empty
    }

    private var isFolded: Bool { controller.foldedSections.contains(id) }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if hasContent {
                    Button {
                        if isFolded { controller.foldedSections.remove(id) } else { controller.foldedSections.insert(id) }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                                .rotationEffect(.degrees(isFolded ? 0 : 90)).frame(width: 10)
                            Text(title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8).padding(.leading, 16)
                }
                if let info { PlotInfoButton(text: info) }
                Spacer(minLength: 0)
                if let isOn { Toggle("", isOn: isOn).labelsHidden().toggleStyle(.checkbox) }
            }
            if hasContent && !isFolded {
                content
                    .padding(.leading, 16)
                    .transition(.opacity)
            }
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Divider() }
    }
}

private struct PlotInfoLabelKey: EnvironmentKey { static let defaultValue = "More details" }

extension EnvironmentValues {
    /// The tooltip of the "i" buttons of an inspector, in the language of the application.
    var plotInfoLabel: String {
        get { self[PlotInfoLabelKey.self] }
        set { self[PlotInfoLabelKey.self] = newValue }
    }
}

extension PlotInspectorSection where Content == EmptyView {
    /// A section that is only its title, its box and its explanation: nothing to fold.
    public init(id: String, title: String, isOn: Binding<Bool>? = nil, info: String? = nil) {
        self.init(id: id, title: title, isOn: isOn, info: info, empty: EmptyView())
    }
}

/// A small "i": the long explanation of a setting, in a popover, so that the inspector keeps to short lines.
public struct PlotInfoButton: View {
    let text: String
    var label: String?
    @Environment(\.plotInfoLabel) private var environmentLabel
    @State private var shown = false

    /// - Parameter label: the tooltip of the button; the one the inspector gives (`PlotLabels.moreDetails`) when it is left out.
    public init(text: String, label: String? = nil) {
        self.text = text
        self.label = label
    }

    public var body: some View {
        Button { shown.toggle() } label: { Image(systemName: "info.circle").foregroundStyle(.secondary) }
            .buttonStyle(.plain)
            .help(label ?? environmentLabel)
            .popover(isPresented: $shown, arrowEdge: .bottom) {
                Text(text).font(.callout).fixedSize(horizontal: false, vertical: true).frame(width: 300, alignment: .leading).padding(14)
            }
    }
}

/// The inspector of a plot, in pages with tabs at the top and folding sections in each, as the format inspector of Keynote has: the
/// channels (when there are several), how the curves are drawn, the phase (when the plot shows one), then the pages of the
/// application. Only the pages that mean something for what the plot shows are in the tabs. The window puts it in an inspector bound
/// to `controller.showsInspector`, and the button of the toolbar shows and hides it.
public struct PlotInspector: View {
    @Bindable var controller: PlotController
    var labels: PlotLabels
    var accent: Color
    var extraTabs: [PlotInspectorTab]
    var leadingTabs: [PlotInspectorTab]

    /// - Parameters:
    ///   - accent: the accent of the application, for the boxes and the links (the system's keeps its own).
    ///   - extraTabs: pages of the application, after those of the plot.
    ///   - leadingTabs: pages of the application that come before those of the plot, the first one being the page that is open at first.
    public init(controller: PlotController, labels: PlotLabels = PlotLabels(), accent: Color = .accentColor, extraTabs: [PlotInspectorTab] = [],
                leadingTabs: [PlotInspectorTab] = []) {
        self.controller = controller
        self.labels = labels
        self.accent = accent
        self.extraTabs = extraTabs
        self.leadingTabs = leadingTabs
    }

    /// The pages that mean something now.
    private var tabs: [PlotInspectorTab] {
        var out: [PlotInspectorTab] = leadingTabs
        if let series = controller.series, series.items.count > 1 {
            out.append(PlotInspectorTab(id: "channels", title: labels.channels) { PlotChannelList(series: series, labels: labels, inInspector: true) })
        }
        // The fill is for the curves that have one (a phase is a line); the smoothing for magnitudes.
        if !controller.hasPhase || controller.hasMagnitude {
            out.append(PlotInspectorTab(id: "display", title: labels.display) { display })
        }
        if controller.hasPhase {
            out.append(PlotInspectorTab(id: "phase", title: labels.phase) { phase })
        }
        return out + extraTabs
    }

    private var selected: PlotInspectorTab? {
        let all = tabs
        return all.first { $0.id == controller.inspectorTab } ?? all.first
    }

    public var body: some View {
        VStack(spacing: 0) {
            let all = tabs
            if all.count > 1 { strip(all) }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let page = selected { page.content }
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .environment(controller)
        .environment(\.plotInfoLabel, labels.moreDetails)
        .tint(accent)
    }

    /// The tabs: on macOS 26 a cell of Liquid Glass each, the one that is open with the accent shining through the glass (a tint of the glass
    /// would read grey); before, a rounded container with the open tab filled with the accent.
    @ViewBuilder private func strip(_ all: [PlotInspectorTab]) -> some View {
        let current = selected?.id
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 6) {
                    ForEach(all) { tab in
                        let isOpen = tab.id == current
                        Button { controller.inspectorTab = tab.id } label: {
                            Text(tab.title)
                                .font(.system(size: 11.5, weight: .semibold))
                                .lineLimit(1).minimumScaleFactor(0.8)
                                .frame(maxWidth: .infinity, minHeight: 26)
                                .foregroundStyle(isOpen ? Color.white : Color.primary.opacity(0.8))
                                .background {
                                    if isOpen {
                                        Capsule().fill(LinearGradient(colors: [accent.opacity(0.6), accent.opacity(0.85)], startPoint: .top, endPoint: .bottom))
                                    }
                                }
                                .glassEffect(.regular.interactive(), in: Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        } else {
            HStack(spacing: 2) {
                ForEach(all) { tab in
                    Button { controller.inspectorTab = tab.id } label: {
                        Text(tab.title)
                            .font(.system(size: 11.5, weight: .medium))
                            .lineLimit(1).minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, minHeight: 24)
                            .foregroundStyle(tab.id == current ? Color.white : Color.primary.opacity(0.75))
                            .background(tab.id == current ? accent : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
    }

    @ViewBuilder private var display: some View {
        @Bindable var options = controller.display
        VStack(alignment: .leading, spacing: 0) {
            if !controller.hasPhase {
                // The fill is always there where a curve has one: what is chosen is its style, not whether it exists.
                PlotInspectorSection(id: "fill", title: labels.fill, info: labels.gradientHelp) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(labels.fillStyle).foregroundStyle(.secondary)
                            Spacer(minLength: 8)
                            Picker(labels.fillStyle, selection: $options.gradient.enabled) {
                                Text(labels.fillGradient).tag(true)
                                Text(controller.fillCanBeNone ? labels.fillNone : labels.fillFlat).tag(false)
                            }
                            .labelsHidden().fixedSize()
                        }
                        Toggle(labels.gradientWithSeveral, isOn: $options.gradient.withSeveral).disabled(!options.gradient.enabled)
                            .toggleStyle(.checkbox)
                    }
                }
            }
            if controller.hasMagnitude { smoothingSection(options: options) }
        }
    }

    @ViewBuilder private var phase: some View {
        @Bindable var options = controller.display
        VStack(alignment: .leading, spacing: 0) {
            PlotInspectorSection(id: "groupDelay", title: labels.groupDelay, isOn: $options.showGroupDelay, info: labels.groupDelayHelp)
            if options.showGroupDelay { smoothingSection(options: options) }
            PlotInspectorSection(id: "phaseCurve", title: labels.phaseCurve) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Toggle(labels.unwrapPhase, isOn: $options.unwrapPhase).disabled(options.showGroupDelay)
                        PlotInfoButton(text: labels.unwrapPhaseHelp)
                    }
                    HStack(spacing: 6) {
                        Toggle(labels.removeDelay, isOn: $options.removeDelay).disabled(options.showGroupDelay)
                        PlotInfoButton(text: labels.removeDelayHelp)
                    }
                    // The value that is taken out, for each phase, and where it comes from.
                    ForEach(controller.phaseDelays, id: \.name) { d in
                        HStack(spacing: 6) {
                            Text(d.name).lineLimit(1)
                            Spacer(minLength: 8)
                            Text(TickLabels.engineering(d.seconds, unit: "s")).monospacedDigit()
                            Text("(" + (d.isEstimated ? labels.delayFitted : labels.delayGiven) + ")").foregroundStyle(.secondary)
                        }
                        .font(.callout)
                        .foregroundStyle(options.removeDelay ? .primary : .secondary)
                    }
                }
                .toggleStyle(.checkbox)
            }
        }
    }

    private func smoothingPicker(options: PlotDisplayOptions) -> some View {
        @Bindable var options = options
        return Picker(labels.smoothing, selection: $options.smoothing) {
            Text(labels.noSmoothing).tag(OctaveSmoothing.none)
            ForEach(OctaveSmoothing.allCases.filter { $0 != .none }, id: \.self) { Text($0.title).tag($0) }
        }
        .labelsHidden()
    }

    @ViewBuilder private func smoothingSection(options: PlotDisplayOptions) -> some View {
        @Bindable var options = options
        PlotInspectorSection(id: "smoothing", title: labels.smoothing, info: labels.smoothingHelp) {
            VStack(alignment: .leading, spacing: 8) {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        Text(labels.smoothingBand).foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        smoothingPicker(options: options).fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(labels.smoothingBand).foregroundStyle(.secondary)
                        smoothingPicker(options: options).frame(maxWidth: .infinity)
                    }
                }
                Toggle(labels.showUnsmoothed, isOn: $options.showsUnsmoothed).toggleStyle(.checkbox).disabled(options.smoothing == .none)
            }
        }
    }
}
