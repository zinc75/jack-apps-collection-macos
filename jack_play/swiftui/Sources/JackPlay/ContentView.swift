// SPDX-License-Identifier: GPL-3.0-or-later

import AppearanceKit
import JackPlayKit
import MatrixKit
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationSplitView {
            Sidebar().navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            Group {
                switch model.page {
                case .play: PlayView()
                case .outputs: OutputsView()
                case .loop: LoopView()
                case .advanced: AdvancedView()
                case .display: DisplayView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .top, spacing: 0) { FailureBanner() }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if model.player.file != nil { ControlsBar() }
            }
        }
        .containerBackground(Color.windowFill, for: .window)
        .task {
            model.start()
            #if DEBUG
            let env = ProcessInfo.processInfo.environment
            if let page = env["JACKPLAY_PAGE"].flatMap(Page.init(rawValue:)) {
                try? await Task.sleep(for: .milliseconds(1500))
                model.page = page
            }
            #endif
        }
        #if DEBUG
        .task {
            let env = ProcessInfo.processInfo.environment
            guard let path = env["JACKPLAY_FILE"] else { return }
            for _ in 0..<100 where !model.graph.isConnected { try? await Task.sleep(for: .milliseconds(100)) }
            model.open(URL(fileURLWithPath: path))
            if env["JACKPLAY_AUTOPLAY"] != nil {
                for _ in 0..<100 where !model.player.isRunning { try? await Task.sleep(for: .milliseconds(100)) }
                model.player.play()
            }
        }
        #endif
        #if DEBUG
        .task {
            // Development aid: JACKPLAY_SNAPSHOT=<file.png> writes the number of the window to <file.png>.id after 5 s, waits 4 s and quits.
            guard let path = ProcessInfo.processInfo.environment["JACKPLAY_SNAPSHOT"] else { return }
            try? await Task.sleep(for: .seconds(5))
            // The number of the window goes to a file, for `screencapture -l` run by the script: only the window is captured.
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
        #if DEBUG
        .task {
            // Development aid: JACKPLAY_CHAIN="a.wav|b.wav|c.wav" plays the files one after the other, as the playlist will: the file that
            // comes next is started in advance, and takes over at the end (the names of the clients change in JACK at each file).
            guard let chain = ProcessInfo.processInfo.environment["JACKPLAY_CHAIN"] else { return }
            let urls = chain.split(separator: "|").map { URL(fileURLWithPath: String($0)) }
            guard let first = urls.first else { return }
            for _ in 0..<100 where !model.graph.isConnected { try? await Task.sleep(for: .milliseconds(100)) }
            var index = 0
            model.player.onFileEnded = {
                let next = index + 1
                guard next < urls.count else { return }
                if model.player.advanceToNext(play: true) {
                    index = next
                    model.player.nextNumber = index + 2 < urls.count + 1 ? index + 2 : nil
                    model.player.nextFile = index + 1 < urls.count ? urls[index + 1] : nil
                } else {
                    index = next
                    model.open(urls[index])
                    Task { for _ in 0..<100 where !model.player.isRunning { try? await Task.sleep(for: .milliseconds(50)) }; model.player.play() }
                }
            }
            model.player.listCount = urls.count > 1 ? urls.count : nil
            model.player.currentNumber = urls.count > 1 ? 1 : nil
            model.player.nextNumber = urls.count > 1 ? 2 : nil
            model.open(first)
            for _ in 0..<100 where !model.player.isRunning { try? await Task.sleep(for: .milliseconds(100)) }
            model.player.nextFile = urls.count > 1 ? urls[1] : nil
            model.player.play()
        }
        #endif
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            model.open(url)
            return true
        }
        .navigationTitle(model.player.file?.url.lastPathComponent ?? "Jack Play")
        .navigationSubtitle("Jack Apps Collection for macOS")
        .toolbar { ToolbarItem(placement: .primaryAction) { JackStatusPill() } }
    }
}

struct JackStatusPill: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let graph = model.graph
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

/// Why nothing plays, at the top of the page.
struct FailureBanner: View {
    @Environment(AppModel.self) private var model

    private var message: LocalizedStringKey? {
        guard case .failed(let failure) = model.player.phase else { return nil }
        switch failure {
        case .noJack: return "Aucun serveur JACK n'est démarré. La lecture commence dès qu'il l'est."
        case .noPlayer: return "Le programme jack_play est introuvable."
        case .cannotOpenFile: return "Ce fichier ne peut pas être lu comme un fichier audio."
        case .playerEnded: return "Le programme jack_play s'est arrêté."
        }
    }

    var body: some View {
        if let message {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text(message)
                Spacer(minLength: 12)
            }
            .foregroundStyle(Color.alert)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Color.alert.opacity(0.12))
            .overlay(alignment: .bottom) { Rectangle().fill(Color.alert.opacity(0.35)).frame(height: 0.5) }
        }
    }
}
