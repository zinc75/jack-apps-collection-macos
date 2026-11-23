// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import JackBridge
import Observation

/// The JACK graph as the link needs it: the clients that have audio outputs (what can be sent) and audio inputs (where what
/// is received can go), and the state of the server. The application opens one JACK client of its own for this, and keeps
/// trying while no server runs.
@MainActor
@Observable
public final class JackGraph: JackLinking {
    public private(set) var isConnected = false
    public private(set) var sampleRate: Int?
    /// The JACK period, in frames: what the advice on the buffer depends on.
    public private(set) var bufferSize: Int?
    /// Clients with audio output ports.
    public private(set) var sources: [JackPortClient] = []
    /// Clients with audio input ports.
    public private(set) var destinations: [JackPortClient] = []

    public static let clientName = "ZitaNetworkBridge-UI"

    /// Clients that are not offered: the programs of the link themselves, whose ports are the ones being wired.
    @ObservationIgnored public var excludedClients: Set<String> = []
    /// Called after the graph has been read again: ports have appeared or gone, connections have been made.
    @ObservationIgnored public var onChange: (() -> Void)?

    let bridge = JackBridgeWrapper()
    @ObservationIgnored let applications: ClientApplications
    @ObservationIgnored private var retry: Task<Void, Never>?
    @ObservationIgnored private var pending: Task<Void, Never>?

    public init() {
        let bridge = bridge
        applications = ClientApplications(metadata: { bridge.coreAudioBoxKey(name: $0) })
        applications.onChange = { [weak self] in self?.applyApplications() }
    }

    /// Connects to the server, and again whenever it comes back after a shutdown.
    public func start() {
        guard retry == nil else { return }
        retry = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if !self.isConnected { self.tryOpen() }
                try? await Task.sleep(for: .seconds(self.isConnected ? 3 : 1.5))
                if self.isConnected { self.pollServerState() }
            }
        }
    }

    public func stop() {
        retry?.cancel(); retry = nil
        pending?.cancel(); pending = nil
        bridge.close()
        isConnected = false
    }

    /// Reads the graph again, now.
    public func refresh() {
        guard bridge.isConnected else { return }
        let audio = bridge.getPorts().filter { $0.type == .audio && $0.clientName != Self.clientName && !excludedClients.contains($0.clientName) }
        var outs = JackPortClient.group(ports: audio.filter { $0.direction == .output }.map(\.id))
        var ins = JackPortClient.group(ports: audio.filter { $0.direction == .input }.map(\.id))
        applications.update(clients: Set((outs + ins).filter { !$0.isSystem }.map(\.name)))
        for list in [0, 1] {
            var groups = list == 0 ? outs : ins
            for i in groups.indices where !groups[i].isSystem {
                groups[i].bundleID = applications.bundles[groups[i].name]
                groups[i].isJackMoebiusMaster = groups[i].name == ClientApplications.jackMoebiusClient || bridge.isJackMoebiusMaster(name: groups[i].name)
            }
            if list == 0 { outs = groups } else { ins = groups }
        }
        sources = outs
        destinations = ins
        sampleRate = Int(bridge.sampleRate)
        bufferSize = Int(bridge.bufferSize)
        onChange?()
    }

    /// The ports of the sound card, in order: the capture ports where a sender gets its sound, the playback ports where a
    /// receiver sends it. These are where a direction is wired the first time.
    public var capturePorts: [String] { sources.first(where: \.isSystem).map { c in c.ports.map { c.fullName(of: $0) } } ?? [] }
    public var playbackPorts: [String] { destinations.first(where: \.isSystem).map { c in c.ports.map { c.fullName(of: $0) } } ?? [] }

    // MARK: JackLinking (all the ports, even those of the clients that are not offered: the programs' own)

    public func outputPorts() -> Set<String> {
        Set(bridge.getPorts().filter { $0.direction == .output && $0.type == .audio }.map(\.id))
    }

    public func inputPorts() -> Set<String> {
        Set(bridge.getPorts().filter { $0.direction == .input && $0.type == .audio }.map(\.id))
    }

    public func destinations(of output: String) -> Set<String> {
        Set(bridge.getConnections().filter { $0.from == output }.map(\.to))
    }

    /// Every audio connection, read at once (the default would read the graph again for each output).
    public func allLinks() -> Set<JackLink> {
        let outputs = outputPorts(), inputs = inputPorts()
        return Set(bridge.getConnections().filter { outputs.contains($0.from) && inputs.contains($0.to) }.map { JackLink(output: $0.from, input: $0.to) })
    }

    public func connect(from output: String, to input: String) throws {
        try bridge.connect(from: output, to: input, fromType: .audio, toType: .audio)
    }

    public func disconnect(from output: String, to input: String) throws {
        try bridge.disconnect(from: output, to: input)
    }

    // MARK: Server

    private func tryOpen() {
        do { try bridge.open(clientName: Self.clientName) } catch { return }
        bridge.onPortRegistration = { [weak self] _, _ in self?.scheduleRefresh() }
        bridge.onPortConnect = { [weak self] _, _ in self?.scheduleRefresh() }
        bridge.onShutdown = { [weak self] in self?.serverStopped() }
        isConnected = true
        refresh()
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

    private func serverStopped() {
        applications.reset()
        bridge.close()
        isConnected = false
        sources = []; destinations = []
        sampleRate = nil; bufferSize = nil
        onChange?()
    }

    private func pollServerState() {
        guard bridge.isConnected else { return }
        applications.update(clients: Set((sources + destinations).filter { !$0.isSystem }.map(\.name)))
        sampleRate = Int(bridge.sampleRate)
        bufferSize = Int(bridge.bufferSize)
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
