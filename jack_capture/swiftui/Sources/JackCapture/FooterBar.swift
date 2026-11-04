// SPDX-License-Identifier: GPL-2.0-or-later

import SwiftUI
import MatrixKit
import JackCaptureKit

struct FooterBar: View {
    @Environment(RecorderModel.self) private var model
    @State private var showsCommand = false
    @State private var nextName = ""
    @State private var available: Int64?

    private var sizeLine: String {
        let perMinute = SizeText.bytes(model.bytesPerMinute)
        let free = available.map { SizeText.bytes(Double($0)) } ?? "?"
        return String(localized: "Environ \(perMinute) par minute · \(free) disponibles")
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                if model.phase.showsStopSymbol {
                    Text(verbatim: model.outputFile ?? nextName).fontWeight(.medium)
                    Text(verbatim: (model.settings.folder as NSString).abbreviatingWithTildeInPath)
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(verbatim: model.settings.summaryLine(sampleRate: model.sampleRate)).fontWeight(.medium)
                    Text(verbatim: sizeLine).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if model.isConfigured || model.phase.showsStopSymbol {
                RecordButton(showsStop: model.phase.showsStopSymbol, isEnabled: model.phase != .stopping) {
                    #if DEBUG
                    model.trace("red button action fired")
                    #endif
                    model.toggleRecording()
                }
            } else {
                ConfigureButton()
            }

            HStack {
                Button("Ligne de commande générée") { showsCommand = true }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .sheet(isPresented: $showsCommand) { CommandSheet() }
        .task(id: model.settings) { nextName = model.nextFileName(); available = model.availableBytes() }
        #if DEBUG
        .task { if ProcessInfo.processInfo.environment["JACKCAPTURE_SHEET"] != nil { showsCommand = true } }
        #endif
        .padding(.horizontal, 24)
        .frame(height: 88)
        // A blurred material of its own: the form scrolls behind it without showing through the texts.
        .background(Color.windowFill)
        .overlay(alignment: .top) { Divider() }
    }
}

/// The big round button: a red glass disc, with the white stop symbol inside while something runs.
struct RecordButton: View {
    let showsStop: Bool
    var isEnabled = true
    /// 54 in the footer; larger on the page of the recording, where the disc breathes softly while it waits.
    var diameter: CGFloat = 54
    var breathes = false
    let action: () -> Void
    @State private var pulse = false
    @State private var isHovered = false
    @State private var breathing = false

    private var scale: CGFloat { diameter / 54 }

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 5)
                .fill(.white)
                .frame(width: 17, height: 17)
                .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                .opacity(showsStop ? 0.96 : 0)
                .scaleEffect(showsStop ? 1 : 0.4)
                .animation(.spring(duration: 0.28), value: showsStop)
                .frame(width: 54, height: 54)
                .redGlassDisc()
                // Under the pointer the disc swells a little and glows red.
                .shadow(color: .red.opacity(isHovered && isEnabled ? 0.55 : (breathes && !showsStop ? (breathing ? 0.4 : 0.1) : 0)),
                        radius: isHovered ? 12 : (breathes && !showsStop ? 16 : 0))
                .scaleEffect(isHovered && isEnabled ? 1.08 : 1)
                .scaleEffect(scale)
                .frame(width: diameter, height: diameter)
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .onHover { hovering in withAnimation(.spring(duration: 0.22, bounce: 0.35)) { isHovered = hovering } }
        .background {
            if showsStop {
                Circle().stroke(.red.opacity(0.35), lineWidth: 2)
                    .frame(width: diameter, height: diameter)
                    .scaleEffect(pulse ? 1.45 : 1)
                    .opacity(pulse ? 0 : 1)
                    .animation(.easeOut(duration: 1.6).repeatForever(autoreverses: false), value: pulse)
                    .onAppear { pulse = true }
                    .onDisappear { pulse = false }
            }
        }
        .disabled(!isEnabled)
        .onAppear {
            guard breathes else { return }
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { breathing = true }
        }
        .accessibilityLabel(showsStop ? "Arrêter l'enregistrement" : "Enregistrer")
        .help(showsStop ? "Arrêter (⌘R)" : "Enregistrer (⌘R)")
    }
}

/// No chrome, and a small dip under the click, as the glass of a button gives.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .animation(.spring(duration: 0.2, bounce: 0.4), value: configuration.isPressed)
    }
}

/// On the first launch the red button is not offered: the recording has to be set up first, starting with the channels.
struct ConfigureButton: View {
    @Environment(RecorderModel.self) private var model

    var body: some View {
        Button("Configurer l'enregistrement") { model.view = .channels }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .help("Choisir les sources, puis le dossier, avant le premier enregistrement.")
    }
}
