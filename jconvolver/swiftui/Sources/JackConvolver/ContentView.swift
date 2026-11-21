// SPDX-License-Identifier: GPL-3.0-or-later

import AppearanceKit
import JConvolverKit
import MatrixKit
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    /// The sidebar and the page. The footer is not inside it (it would stop at the sidebar) but below it: it runs under both,
    /// over the whole width of the window, and the sidebar and the pages end where it begins.
    private var splitView: some View {
        NavigationSplitView {
            Sidebar().navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            Group {
                switch model.page {
                case .home: HomeView()
                case .matrix: MatrixView()
                case .ports: PortsView()
                case .launch: LaunchView()
                case .log: LogView()
                case .display: DisplayView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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
            let env = ProcessInfo.processInfo.environment
            if let path = env["JACKCONVOLVER_OPEN"] { model.open(URL(fileURLWithPath: path)) }
            if let page = env["JACKCONVOLVER_PAGE"].flatMap(Page.init(rawValue:)) { model.page = page }
            if env["JACKCONVOLVER_VIEW"] == "table" { model.viewMode = .table }
            if env["JACKCONVOLVER_SHEET"] == "names" { try? await Task.sleep(for: .milliseconds(800)); model.showsPortNames = true }
            if env["JACKCONVOLVER_SHEET"] == "detail", let d = model.document,
               let first = d.content.impulses.keys.sorted().first(where: { pair in d.impulses(at: pair).contains { if case .file = $0.source { true } else { false } } }),
               let i = d.impulses(at: first).firstIndex(where: { if case .file = $0.source { true } else { false } }) {
                try? await Task.sleep(for: .milliseconds(800)); model.detail = DetailTarget(pair: first, index: i)
            }
            if env["JACKCONVOLVER_AUTORUN"] != nil {
                try? await Task.sleep(for: .seconds(2))
                model.toggleRun()
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
        .navigationTitle("Jack Convolver")
        .navigationSubtitle("Jack Apps Collection for macOS")
        .toolbar { ToolbarItem(placement: .primaryAction) { JackStatusPill() } }
        .sheet(isPresented: $model.showsNewConfiguration) { NewConfigurationSheet() }
        .sheet(isPresented: $model.showsCommand) { CommandSheet() }
        .sheet(isPresented: $model.showsPortNames) { PortNamesSheet() }
        .sheet(item: $model.detail) { ImpulseDetailSheet(target: $0) }
        .sheet(isPresented: $model.showsProblems) { ProblemsSheet() }
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
