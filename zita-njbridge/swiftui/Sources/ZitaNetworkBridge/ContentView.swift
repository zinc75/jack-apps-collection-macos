// SPDX-License-Identifier: GPL-3.0-or-later

import AppearanceKit
import MatrixKit
import SwiftUI
import ZitaBridgeKit

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
                case .link: LinkView()
                case .network: PlaceholderView(title: "Réseau")
                case .lanes: PlaceholderView(title: "Voies")
                case .flow: PlaceholderView(title: "Flux")
                case .display: PlaceholderView(title: "Affichage")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .top, spacing: 0) { FailureBanner() }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            splitView
            FooterBar()
        }
        .containerBackground(Color.windowFill, for: .window)
        .task {
            model.start()
            #if DEBUG
            let env = ProcessInfo.processInfo.environment
            if let page = env["ZITABRIDGE_PAGE"].flatMap(Page.init(rawValue:)) {
                try? await Task.sleep(for: .milliseconds(1500))
                model.page = page
            }
            if env["ZITABRIDGE_AUTOSTART"] != nil {
                for _ in 0..<100 where !model.controller.graph.isConnected { try? await Task.sleep(for: .milliseconds(100)) }
                model.controller.toggleAll()
            }
            #endif
        }
        #if DEBUG
        .task {
            // Development aid: ZITABRIDGE_SNAPSHOT=<file.png> writes the number of the window to <file.png>.id after 7 s, waits 4 s and quits.
            guard let path = ProcessInfo.processInfo.environment["ZITABRIDGE_SNAPSHOT"] else { return }
            try? await Task.sleep(for: .seconds(7))
            if let window = NSApp.windows.first(where: { $0.isVisible }) {
                NSApp.activate()
                window.makeKeyAndOrderFront(nil)
                try? await Task.sleep(for: .milliseconds(600))
                try? String(window.windowNumber).write(toFile: path + ".id", atomically: true, encoding: .utf8)
            }
            try? await Task.sleep(for: .seconds(4))
            NSApp.terminate(nil)
        }
        #endif
        .navigationTitle("Zita Network Bridge")
        .navigationSubtitle("Jack Apps Collection for macOS")
        .toolbar { ToolbarItem(placement: .primaryAction) { JackStatusPill() } }
    }
}

struct JackStatusPill: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let graph = model.controller.graph
        HStack(spacing: 6) {
            Circle().fill(graph.isConnected ? Color.green : Color.red).frame(width: 8, height: 8)
            Group {
                if graph.isConnected, let rate = graph.sampleRate, let frames = graph.bufferSize {
                    let kHz = (Double(rate) / 1000).formatted(.number.precision(.fractionLength(0...1)))
                    Text("JACK · \(kHz) kHz · \(frames) trames")
                } else if graph.isConnected {
                    Text(verbatim: "JACK")
                } else {
                    Text("JACK non démarré")
                }
            }
            .font(.caption).fontWeight(.medium)
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .help(graph.isConnected ? "Serveur JACK connecté" : "Aucun serveur JACK n'est démarré.")
    }
}

/// Why something does not run, at the top of the page: no JACK server, a program that is missing, a refusal of a program.
struct FailureBanner: View {
    @Environment(AppModel.self) private var model

    private var messages: [LocalizedStringKey] {
        var found = [LocalizedStringKey]()
        let c = model.controller
        if !c.graph.isConnected, c.anyArmedRuns { found.append("Aucun serveur JACK n'est démarré. La liaison en a besoin.") }
        for direction in c.armedDirections {
            if case .failed(let text) = model.state(of: direction) { found.append(LocalizedStringKey(text)) }
        }
        return found
    }

    var body: some View {
        let shown = messages
        if !shown.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(shown.enumerated()), id: \.offset) { _, message in
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(message)
                        Spacer(minLength: 12)
                    }
                }
            }
            .foregroundStyle(Color.alert)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Color.alert.opacity(0.12))
            .overlay(alignment: .bottom) { Rectangle().fill(Color.alert.opacity(0.35)).frame(height: 0.5) }
        }
    }
}

/// A page that is not written yet.
struct PlaceholderView: View {
    let title: LocalizedStringKey
    var body: some View {
        Text(title).font(.title2).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
