// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import JackBridge
import Observation

/// The state of the JACK server as the application shows it: whether it runs, its rate and its period, the audio cuts
/// (xruns), and the ports of the other clients, for the page of the connections. The application opens a JACK client of its
/// own for this and keeps trying while no server runs.
@MainActor
@Observable
public final class JackStatus {
    public private(set) var isConnected = false
    public private(set) var sampleRate: Int?
    /// The JACK period, in frames.
    public private(set) var bufferSize: Int?
    /// The xruns since the application connected.
    public private(set) var xrunCount = 0
    /// The audio load of the server, in percent of the time of a period; nil while the server does not say.
    public private(set) var cpuLoad: Double?

    /// The audio ports of the graph and the connections between them, as they really are: whoever made them.
    public private(set) var audioOutputs: Set<String> = []
    public private(set) var audioInputs: Set<String> = []
    public private(set) var links: Set<JackLink> = []
    /// Called when the connections have changed (after the graph was read again).
    @ObservationIgnored public var onLinksChanged: (() -> Void)?

    /// Clients with audio output ports: what can feed an input of jconvolver.
    public private(set) var sources: [JackPortClient] = []
    /// Clients with audio input ports: where an output of jconvolver can go.
    public private(set) var destinations: [JackPortClient] = []

    public static let clientName = "JackConvolver-UI"

    /// Clients that are not offered: jconvolver itself, whose ports are the ones being connected.
    @ObservationIgnored public var excludedClients: Set<String> = [] { didSet { if oldValue != excludedClients { refresh() } } }

    /// Called with the number of xruns that came since the last reading.
    @ObservationIgnored public var onXruns: ((Int) -> Void)?
    @ObservationIgnored private let bridge = JackBridgeWrapper()
    @ObservationIgnored private let applications: ClientApplications
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var lastXruns: UInt32 = 0

    public init() {
        let bridge = bridge
        applications = ClientApplications(metadata: { bridge.coreAudioBoxKey(name: $0) })
        applications.onChange = { [weak self] in self?.applyApplications() }
    }

    /// Connects to the server, and again whenever it comes back after a shutdown.
    public func start(interval: Duration = .seconds(1)) {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if !self.isConnected { self.tryOpen() } else { self.poll() }
                try? await Task.sleep(for: interval)
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
        pending?.cancel(); pending = nil
        bridge.close()
        sources = []; destinations = []
        links = []; audioOutputs = []; audioInputs = []
        isConnected = false
        sampleRate = nil
        bufferSize = nil
        cpuLoad = nil
    }

    private func tryOpen() {
        do { try bridge.open(clientName: Self.clientName) } catch { return }
        bridge.onShutdown = { [weak self] in Task { @MainActor in self?.serverStopped() } }
        bridge.onPortRegistration = { [weak self] _, _ in Task { @MainActor in self?.scheduleRefresh() } }
        bridge.onPortConnect = { [weak self] _, _ in Task { @MainActor in self?.scheduleRefresh() } }
        bridge.resetXrunCount()
        lastXruns = 0
        isConnected = true
        poll()
        refresh()
    }

    private func serverStopped() {
        applications.reset()
        bridge.close()
        isConnected = false
        sources = []; destinations = []
        links = []; audioOutputs = []; audioInputs = []
        sampleRate = nil
        bufferSize = nil
        cpuLoad = nil
    }

    private func poll() {
        guard bridge.isConnected else { serverStopped(); return }
        sampleRate = Int(bridge.sampleRate)
        let frames = Int(bridge.bufferSize)
        bufferSize = frames > 0 ? frames : nil
        cpuLoad = bridge.cpuLoad.map { Double($0) }
        let count = bridge.xrunCount
        if count > lastXruns {
            let new = Int(count - lastXruns)
            lastXruns = count
            xrunCount += new
            onXruns?(new)
        }
    }

    // MARK: The ports of the other clients

    /// Reads the graph again, now.
    public func refresh() {
        guard bridge.isConnected else { return }
        let audio = bridge.getPorts().filter { $0.type == .audio && $0.clientName != Self.clientName && !excludedClients.contains($0.clientName) }
        var outs = JackPortClient.group(ports: audio.filter { $0.direction == .output }.map(\.id))
        var ins = JackPortClient.group(ports: audio.filter { $0.direction == .input }.map(\.id))
        applications.update(clients: Set((outs + ins).filter { !$0.isSystem }.map(\.name)))
        func decorate(_ groups: inout [JackPortClient]) {
            for i in groups.indices where !groups[i].isSystem {
                groups[i].bundleID = applications.bundles[groups[i].name]
                groups[i].isJackMoebiusMaster = groups[i].name == ClientApplications.jackMoebiusClient || bridge.isJackMoebiusMaster(name: groups[i].name)
            }
        }
        decorate(&outs); decorate(&ins)
        sources = outs
        destinations = ins
        let outputNames = Set(audio.filter { $0.direction == .output }.map(\.id)), inputNames = Set(audio.filter { $0.direction == .input }.map(\.id))
        let found = Set(bridge.getConnections().filter { outputNames.contains($0.from) && inputNames.contains($0.to) }.map { JackLink(output: $0.from, input: $0.to) })
        audioOutputs = outputNames
        audioInputs = inputNames
        if found != links {
            links = found
            onLinksChanged?()
        }
    }

    /// The ports of the sound card, in order: the capture ports where an input gets its sound, the playback ports where an
    /// output sends it. They are what "back to the sound card" connects the channels to.
    public var capturePorts: [String] { sources.first(where: \.isSystem).map { c in c.ports.map { c.fullName(of: $0) } } ?? [] }
    public var playbackPorts: [String] { destinations.first(where: \.isSystem).map { c in c.ports.map { c.fullName(of: $0) } } ?? [] }

    /// Connects while jconvolver runs, so that a change on the page of the connections is heard at once. A port that does not
    /// exist (yet) is not an error: the configuration file makes the connection the next time the program starts.
    public func connect(from output: String, to input: String) {
        try? bridge.connect(from: output, to: input, fromType: .audio, toType: .audio)
    }

    public func disconnect(from output: String, to input: String) {
        try? bridge.disconnect(from: output, to: input)
    }

    private func applyApplications() {
        func filled(_ clients: [JackPortClient]) -> [JackPortClient]? {
            var groups = clients, changed = false
            for i in groups.indices where !groups[i].isSystem && groups[i].bundleID == nil {
                if let id = applications.bundles[groups[i].name] { groups[i].bundleID = id; changed = true }
            }
            return changed ? groups : nil
        }
        if let groups = filled(sources) { sources = groups }
        if let groups = filled(destinations) { destinations = groups }
    }

    /// Port events come in bursts (a client registers all its ports at once): one read for the burst.
    private func scheduleRefresh() {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            if !Task.isCancelled { self?.refresh() }
        }
    }
}
