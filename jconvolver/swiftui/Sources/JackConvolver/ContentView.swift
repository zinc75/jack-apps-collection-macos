// SPDX-License-Identifier: GPL-3.0-or-later

import AppearanceKit
import JConvolverKit
import MatrixKit
import PlotKit
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.appAccentColor) private var accent

    /// The sidebar and the page. The footer is not inside it (it would stop at the sidebar) but below it: it runs under both,
    /// over the whole width of the window, and the sidebar and the pages end where it begins.
    private var splitView: some View {
        NavigationSplitView {
            Sidebar().navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            ZStack {
                Group {
                    switch model.page {
                    case .home: HomeView()
                    case .matrix: MatrixView()
                    case .impulse: Color.clear
                    case .ports: ConnectionsView()
                    case .launch: LaunchView()
                    case .config: ConfigFilePage()
                    case .log: LogView()
                    case .display: DisplayView()
                    }
                }
                // The page of an impulse response is kept (hidden) once it has been opened: its view, its zoom and its inspector are still there
                // when one comes back from the matrix.
                if model.detail != nil || model.page == .impulse {
                    // It has no size while it is hidden, so that nothing of it can take what is meant for the page that is shown.
                    let shown = model.page == .impulse
                    ImpulseDetailPage()
                        .frame(maxWidth: shown ? .infinity : 0, maxHeight: shown ? .infinity : 0)
                        .clipped()
                        .opacity(shown ? 1 : 0)
                        .allowsHitTesting(shown)
                        .accessibilityHidden(!shown)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The title of the window, as the system draws it: the application, the configuration that is open, and "Modifié" while it has changes that are not saved.
    private var windowTitle: String {
        guard model.isOpen else { return "Jack Convolver" }
        let name = model.displayName + (model.isCopy ? " (" + String(localized: "copie") + ")" : "")
        return "Jack Convolver · " + name + (model.isEdited ? " — " + String(localized: "Modifié") : "")
    }

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            splitView
            FooterBar()
        }
        .containerBackground(Color.windowFill, for: .window)
        .task {
            model.start()
            #if DEBUG
            // Debug aids: JACKCONVOLVER_OPEN=<file.conf> opens a configuration, JACKCONVOLVER_PAGE=<home|matrix|ports|launch|log|display>
            // shows a page, JACKCONVOLVER_AUTORUN starts the engine.
            // Only the first window: another one, opened by hand, must not do it all again.
            let env = model.hub.sessions.first === model ? ProcessInfo.processInfo.environment : [:]
            if let path = env["JACKCONVOLVER_OPEN"] { model.open(URL(fileURLWithPath: path)) }
            if let page = env["JACKCONVOLVER_PAGE"].flatMap(Page.init(rawValue:)) { model.page = page }
            if env["JACKCONVOLVER_VIEW"] == "table" { model.viewMode = .table }
            if env["JACKCONVOLVER_SHEET"] == "config" { try? await Task.sleep(for: .milliseconds(800)); model.page = .config }
            if env["JACKCONVOLVER_SHEET"] == "render" { try? await Task.sleep(for: .milliseconds(800)); model.showsRender = true }
            if env["JACKCONVOLVER_SHEET"] == "gestures" { try? await Task.sleep(for: .milliseconds(800)); model.showsGestures = true }
            if env["JACKCONVOLVER_SHEET"] == "names" { try? await Task.sleep(for: .milliseconds(800)); model.showsPortNames = true }
            if env["JACKCONVOLVER_SHEET"] == "detail", let d = model.document,
               let first = d.content.impulses.keys.sorted().first(where: { pair in d.impulses(at: pair).contains { if case .file = $0.source { true } else { false } } }),
               let i = d.impulses(at: first).firstIndex(where: { if case .file = $0.source { true } else { false } }) {
                try? await Task.sleep(for: .milliseconds(800)); model.inspect(DetailTarget(pair: first, index: i))
            }
            // JACKCONVOLVER_FAKEDRAG=over|drop: drags the first file of the list over the cell of the third input and third output
            // (what the pointer does), and for "drop" lets go of it.
            if let fake = env["JACKCONVOLVER_FAKEDRAG"], !fake.isEmpty, let file = model.binFiles.first {
                try? await Task.sleep(for: .seconds(2))
                model.beginItemDrag((1...max(1, file.info.channels)).map { .channel(path: file.path, channel: $0) })
                let f = model.matrixContentFrame, cs = model.cellSize
                model.dragPointer = CGPoint(x: f.minX + 76 + 2.5 * cs, y: f.minY + 64 + 2.5 * cs)
                if fake == "panel" { let p = model.selectionPanelFrame; model.dragPointer = CGPoint(x: p.midX, y: p.midY) }
                if fake == "drop" { try? await Task.sleep(for: .seconds(1)); model.endItemDrag() }
            }
            // JACKCONVOLVER_FAKEHOVER=<input>,<output>: the pointer is above that cell (numbers from 1).
            if let spec = env["JACKCONVOLVER_FAKEHOVER"] {
                try? await Task.sleep(for: .seconds(2))
                let n = spec.split(separator: ",").compactMap { Int($0) }
                if n.count == 2 {
                    let cs = model.cellSize
                    model.hoverPair = ConvPair(input: n[0] - 1, output: n[1] - 1)
                    model.hoverPoint = CGPoint(x: 76 + (CGFloat(n[1]) - 0.5) * cs, y: 64 + (CGFloat(n[0]) - 0.5) * cs)
                }
            }
            // JACKCONVOLVER_MODE=file, JACKCONVOLVER_INPUT=<file>, JACKCONVOLVER_OUTPUT=<file>: the mode on sound files, with its files.
            if env["JACKCONVOLVER_MODE"] == "file" { model.mode = .file }
            if let path = env["JACKCONVOLVER_INPUT"], !path.isEmpty { model.inputFile = URL(fileURLWithPath: path) }
            if let path = env["JACKCONVOLVER_OUTPUT"], !path.isEmpty { model.outputFile = URL(fileURLWithPath: path) }
            if let run = env["JACKCONVOLVER_AUTORUN"], !run.isEmpty {
                try? await Task.sleep(for: .seconds(2))
                if model.mode == .file { model.showsRender = true; model.startRun() } else { model.toggleRun() }
            }
            #endif
        }
        #if DEBUG
        .task {
            // Development aid: JACKCONVOLVER_SNAPSHOT=<file.png> writes the number of the window to <file.png>.id after 5 s, waits
            // 4 s and quits. JACKCONVOLVER_WINDOW=<width>x<height> sizes the window; JACKCONVOLVER_SNAPSHOT_DELAY=<seconds> waits longer.
            let env = ProcessInfo.processInfo.environment
            guard let path = env["JACKCONVOLVER_SNAPSHOT"] else { return }
            try? await Task.sleep(for: .seconds(env["JACKCONVOLVER_SNAPSHOT_DELAY"].flatMap(Double.init) ?? 5))
            if let window = NSApp.windows.first(where: { $0.isVisible }) {
                let size = env["JACKCONVOLVER_WINDOW"]?.split(separator: "x").compactMap { Double($0) }
                if let size, size.count == 2 { window.setContentSize(NSSize(width: size[0], height: size[1])); try? await Task.sleep(for: .milliseconds(800)) }
                NSApp.activate()
                window.makeKeyAndOrderFront(nil)
                try? await Task.sleep(for: .milliseconds(600))
                try? String(window.windowNumber).write(toFile: path + ".id", atomically: true, encoding: .utf8)
            }
            try? await Task.sleep(for: .seconds(4))
            NSApp.terminate(nil)
        }
        #endif
        .onChange(of: model.jack.sampleRate) { _, _ in model.refreshProblems() }
        .onChange(of: model.controller.isRunning) { _, _ in model.engineRunningChanged() }
        .alert("Reporter les branchements dans le fichier de configuration ?", isPresented: $model.showsApplyWiring) {
            Button("Appliquer") { model.applyPendingWiring() }
            Button("Ne pas appliquer", role: .cancel) { model.discardPendingWiring() }
        } message: {
            Text("Les branchements faits pendant que le moteur était en cours d'exécution ne sont pas ceux du fichier de configuration utilisé.")
        }
        .navigationTitle(windowTitle)
        .navigationSubtitle("Jack Apps Collection for macOS")
        .toolbar {
            // The tools of the page come first, the state of JACK always last: it is not part of them.
            if model.page == .matrix, model.isOpen { MatrixToolbar(model: model) }
            if model.page == .impulse, model.detail != nil {
                PlotToolbarContent(controller: model.plotController, labels: .localized, accent: accent, includesInspectorControls: true)
            }
            // Under macOS 26 the items of a placement share glass capsules: the pill draws its own, apart from the tools.
            if #available(macOS 26, *) {
                ToolbarSpacer(.fixed, placement: .primaryAction)
                ToolbarItem(placement: .primaryAction) {
                    JackStatusPill()
                        // As high as the other capsules of the toolbar.
                        .padding(.horizontal, 10).frame(height: 36)
                        .glassEffect(.regular, in: Capsule())
                }
                .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .primaryAction) { JackStatusPill() }
            }
        }
        .sheet(isPresented: $model.showsNewConfiguration) { NewConfigurationSheet() }
        .sheet(isPresented: $model.showsCommand) { CommandSheet() }
        .sheet(isPresented: $model.showsPortNames) { PortNamesSheet() }
        .sheet(isPresented: $model.showsResize) { ResizeSheet() }
        .sheet(isPresented: $model.showsGestures) { GesturesSheet() }
        .sheet(isPresented: $model.showsRender) { RenderSheet() }
        .sheet(isPresented: $model.showsProblems) { ProblemsSheet() }
        .sheet(isPresented: $model.showsResolver) { ResolvePathsSheet() }
        .sheet(isPresented: $model.showsPortable) { PortableExportSheet() }
        .sheet(isPresented: $model.showsFade) { FadeSheet() }
        .alert(model.message ?? "", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("OK") { model.message = nil }
        }
    }
}

struct JackStatusPill: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let jack = model.jack
        HStack(spacing: 6) {
            Circle().fill(jack.isConnected ? Color.green : Color.red).frame(width: 8, height: 8)
            Group {
                if jack.isConnected, let rate = jack.sampleRate, let frames = jack.bufferSize {
                    let kHz = (Double(rate) / 1000).formatted(.number.precision(.fractionLength(0...1)))
                    Text("JACK · \(kHz) kHz · \(frames) trames")
                } else if jack.isConnected {
                    Text(verbatim: "JACK")
                } else {
                    Text("JACK non démarré")
                }
            }
            .font(.caption).fontWeight(.medium)
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .help(jack.isConnected ? "Serveur JACK connecté" : "Aucun serveur JACK n'est démarré.")
    }
}
