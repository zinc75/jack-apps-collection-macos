// SPDX-License-Identifier: GPL-2.0-or-later

import SwiftUI
import MatrixKit
import JackCaptureKit

struct ContentView: View {
    @Environment(RecorderModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            Group {
                switch model.view {
                case .recording: RecordingView()
                default: ConfigurationView(section: model.view)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                // The idle page of the recording has its own red button and its own summary: the footer only holds the
                // command button there, at the same place as on every page.
                FooterBar(commandOnly: model.view == .recording && model.phase == .configuration)
            }
            // A failure stays on screen, at the top of the page (under the toolbar, beside the sidebar), until it is
            // closed or the next recording starts.
            .safeAreaInset(edge: .top, spacing: 0) {
                if let message = model.errorMessage {
                    ErrorBanner(message: message) { model.errorMessage = nil }
                }
            }
        }
        // Plain window background: only the blocks are Liquid Glass. The toolbar keeps its own scroll-edge fade.
        .containerBackground(Color.windowFill, for: .window)
        .task { model.graph.start(); model.startLevelLoop() }
        .onChange(of: model.settings) { model.saveSettings() }
        .onChange(of: model.graph.clients) { model.rememberBundles() }
        .sheet(isPresented: $model.asksToConfirm) { StartWarningSheet() }
        #if DEBUG
        .task {
            // Development trace: every click of the main window, and the view it lands on.
            NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { event in
                let point = event.locationInWindow
                let hit = event.window?.contentView?.hitTest(point).map { String(describing: type(of: $0)) } ?? "none"
                model.trace("click in \"\(event.window?.title ?? "?")\" at (\(Int(point.x)), \(Int(point.y))) key=\(event.window?.isKeyWindow ?? false) hit=\(hit)")
                return event
            }
        }
        #endif
        // jack_capture does not outlive the application.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in model.shutdown() }
        #if DEBUG
        .task {
            // Development aid: JACKCAPTURE_PAGE=channels opens that page (recording, channels, file, startStop, advanced, display).
            // The page is opened once the window is up, so that no text field of it takes the initial focus.
            if let page = ProcessInfo.processInfo.environment["JACKCAPTURE_PAGE"].flatMap(MainView.init(rawValue:)) {
                try? await Task.sleep(for: .milliseconds(1500))
                model.view = page
            }
        }
        .task {
            // Development aid: JACKCAPTURE_AUTOREC=<seconds> records for that long without touching the interface;
            // JACKCAPTURE_AUTOSRC="a:1+b:1,a:2" sets the sources (channels separated by ",", sources by "+").
            let env = ProcessInfo.processInfo.environment
            // Without AUTOREC the settings are only applied: the red button is left to the user.
            let secs = env["JACKCAPTURE_AUTOREC"].flatMap(Double.init)
            guard secs != nil || env["JACKCAPTURE_AUTOSRC"] != nil || env["JACKCAPTURE_AUTOFMT"] != nil || env["JACKCAPTURE_AUTOMON"] != nil || env["JACKCAPTURE_AUTONAME"] != nil else { return }
            if env["JACKCAPTURE_AUTOMON"] != nil { model.settings.monitorsLevels = true }
            for _ in 0..<100 where !model.graph.isConnected { try? await Task.sleep(for: .milliseconds(100)) }
            if let spec = env["JACKCAPTURE_AUTOSRC"] {
                let channels = spec.split(separator: ",", omittingEmptySubsequences: false).map { $0.split(separator: "+").map(String.init) }
                model.settings.setChannels(channels.count)
                model.settings.sources = channels
            }
            if let fmt = env["JACKCAPTURE_AUTOFMT"].flatMap(CaptureFormat.init(rawValue:)) { model.settings.setFormat(fmt) }
            if let dir = env["JACKCAPTURE_AUTODIR"] { model.settings.folder = dir }
            if let name = env["JACKCAPTURE_AUTONAME"] { model.settings.name = name }
            if env["JACKCAPTURE_AUTOTME"] != nil { model.settings.writesTimeFile = true }
            if let seconds = env["JACKCAPTURE_AUTOSTOP"].flatMap(Int.init) { model.settings.scheduledStop = true; model.settings.durationSeconds = seconds }
            guard let secs else { return }
            if env["JACKCAPTURE_AUTOTM"] != nil { model.settings.timemachine = true }
            if env["JACKCAPTURE_AUTOJT"] != nil { model.settings.startMode = .transport }
            print("AUTOREC command:", model.command.displayText)
            if env["JACKCAPTURE_AUTOJT"] != nil { model.graph.setTransportRolling(false); try? await Task.sleep(for: .milliseconds(500)) }
            model.toggleRecording()
            print("AUTOREC phase after start:", model.phase, "error:", model.errorMessage ?? "-")
            if env["JACKCAPTURE_AUTOJT"] != nil {
                try? await Task.sleep(for: .seconds(3))
                print("AUTOREC phase while the transport is stopped:", model.phase, "bytes:", model.bytesWritten)
                model.graph.setTransportRolling(true)
                try? await Task.sleep(for: .seconds(2))
                print("AUTOREC phase after the transport rolls:", model.phase, "bytes:", model.bytesWritten)
            }
            if model.settings.timemachine {
                try? await Task.sleep(for: .seconds(2))
                model.toggleRecording()   // the second press starts the file
                print("AUTOREC phase after the second press:", model.phase)
            }
            try? await Task.sleep(for: .seconds(secs))
            print("AUTOREC phase before the stop:", model.phase)
            print("AUTOREC file:", model.outputFile ?? "-", "size:", model.bytesWritten, "status:", String(describing: model.status), "warnings:", model.warnings)
            model.toggleRecording()
            for _ in 0..<100 where model.phase != .done && model.phase != .configuration { try? await Task.sleep(for: .milliseconds(100)) }
            print("AUTOREC final phase:", model.phase, "file:", model.recordedURL?.path ?? "-", "size:", model.bytesWritten, "warnings:", model.warnings, "error:", model.errorMessage ?? "-")
            fflush(stdout)
        }
        .task { if let state = ProcessInfo.processInfo.environment["JACKCAPTURE_STATE"] { await model.preview(state) } }
        #endif
        .navigationTitle("Jack Capture")
        .navigationSubtitle("Jack Apps Collection for macOS")
        .toolbar { MainToolbar() }
    }
}

/// Toolbar items: the JACK status.
struct MainToolbar: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) { JackStatusPill() }
    }
}

/// Connection to the JACK server. A fixed text for now: the real values come with the JACK bridge.
struct JackStatusPill: View {
    @Environment(RecorderModel.self) private var model

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
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .help(graph.isConnected ? "Serveur JACK connecté" : "Aucun serveur JACK n'est démarré.")
    }
}

/// A failure to start or to go on recording, in the colour of the alerts.
struct ErrorBanner: View {
    let message: String
    let close: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
            VStack(alignment: .leading, spacing: 2) {
                Text("Impossible d'enregistrer").fontWeight(.semibold)
                Text(verbatim: message).textSelection(.enabled)
            }
            Spacer(minLength: 12)
            Button("Fermer", action: close).buttonStyle(.borderless)
        }
        .foregroundStyle(Color.alert)
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Color.alert.opacity(0.12))
        .overlay(alignment: .bottom) { Rectangle().fill(Color.alert.opacity(0.35)).frame(height: 0.5) }
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .combine)
    }
}
