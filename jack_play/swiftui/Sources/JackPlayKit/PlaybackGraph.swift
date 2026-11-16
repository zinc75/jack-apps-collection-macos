// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import JackBridge
import Observation

/// A JACK client that has audio inputs: somewhere the player can be connected.
public struct JackDestinationClient: Identifiable, Equatable, Sendable {
    public var id: String { name }
    public let name: String
    /// Port names without the client part, in the order JACK lists them.
    public var ports: [String]
    /// The sound card: its inputs are the playback ports of the system, shown as "system (playback)".
    public let isPlayback: Bool
    /// Bundle identifier of the application a JackMoebius box stands for, if any.
    public var bundleID: String?

    public init(name: String, ports: [String], isPlayback: Bool, bundleID: String? = nil) {
        self.name = name
        self.ports = ports
        self.isPlayback = isPlayback
        self.bundleID = bundleID
    }

    public var displayName: String { isPlayback ? "system (playback)" : name }
    public func fullName(of port: String) -> String { "\(name):\(port)" }
}

/// The JACK graph as the player needs it: the audio inputs by client, where its outputs can go, and the state of the
/// server. The application opens one JACK client of its own for this, and keeps trying while no server runs.
@MainActor
@Observable
public final class PlaybackGraph: PlaybackServer {
    public private(set) var isConnected = false
    public private(set) var sampleRate: Int?
    public private(set) var bufferSize: Int?
    public private(set) var destinations: [JackDestinationClient] = []
    /// Every client of the graph, with ports of any kind: the names that are taken.
    public private(set) var clientNames: Set<String> = []
    public private(set) var xruns = 0

    public static let clientName = "JackPlay-UI"

    /// Called after the graph has been read again: ports have appeared or gone, connections have been made.
    @ObservationIgnored public var onChange: (() -> Void)?

    let bridge = JackBridgeWrapper()
    @ObservationIgnored private var retry: Task<Void, Never>?
    @ObservationIgnored private var pending: Task<Void, Never>?

    public init() {}

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
        let ports = bridge.getPorts()
        let inputs = ports.filter { $0.direction == .input && $0.type == .audio && $0.clientName != Self.clientName }
        var groups = Self.groupClients(inputPorts: inputs.map(\.id))
        for i in groups.indices where !groups[i].isPlayback {
            groups[i].bundleID = bridge.coreAudioBoxKey(name: groups[i].name)
        }
        destinations = groups
        clientNames = Set(ports.map(\.clientName))
        sampleRate = Int(bridge.sampleRate)
        bufferSize = Int(bridge.bufferSize)
        onChange?()
    }

    /// The playback ports of the system, in order: where a file goes the first time.
    public var playbackPorts: [String] {
        guard let system = destinations.first(where: \.isPlayback) else { return [] }
        return system.ports.map { system.fullName(of: $0) }
    }

    // MARK: Transport

    public func transportStart() { bridge.transportStart() }
    /// Stops the transport where it is.
    public func transportPause() { bridge.transportPause() }
    /// Stops the transport and goes back to the start.
    public func transportStop() { bridge.transportStop() }
    public func transportLocate(frame: UInt32) { bridge.transportLocate(frame: frame) }

    // MARK: JackLinking

    public func inputPorts() -> Set<String> {
        Set(bridge.getPorts().filter { $0.direction == .input && $0.type == .audio }.map(\.id))
    }

    public func destinations(of output: String) -> Set<String> {
        Set(bridge.getConnections().filter { $0.from == output }.map(\.to))
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

    private func serverStopped() {
        bridge.close()
        isConnected = false
        destinations = []
        clientNames = []
        sampleRate = nil
        bufferSize = nil
        onChange?()
    }

    private func pollServerState() {
        guard bridge.isConnected else { return }
        sampleRate = Int(bridge.sampleRate)
        bufferSize = Int(bridge.bufferSize)
        xruns = Int(bridge.xrunCount)
    }

    /// Port events come in bursts (a client registers all its ports at once): one read for the burst.
    private func scheduleRefresh() {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            if !Task.isCancelled { self?.refresh() }
        }
    }

    // MARK: Pure part, tested without a server

    /// Groups input ports by client. The system (the sound card) comes first, the others by name.
    nonisolated static func groupClients(inputPorts: [String]) -> [JackDestinationClient] {
        var order: [String] = []
        var ports: [String: [String]] = [:]
        for full in inputPorts {
            guard let colon = full.firstIndex(of: ":") else { continue }
            let client = String(full[..<colon]), port = String(full[full.index(after: colon)...])
            if ports[client] == nil { order.append(client) }
            ports[client, default: []].append(port)
        }
        let groups = order.map { JackDestinationClient(name: $0, ports: ports[$0] ?? [], isPlayback: $0 == "system") }
        return groups.sorted {
            if $0.isPlayback != $1.isPlayback { return $0.isPlayback }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}
