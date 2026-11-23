// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import JackBridge
import Observation

/// A JACK client that has audio inputs: somewhere the player can be connected. The type is the one the tools of the collection
/// share; for the player the sound card is the "playback" one.
public typealias JackDestinationClient = JackPortClient

extension JackPortClient {
    public init(name: String, ports: [String], isPlayback: Bool, bundleID: String? = nil, isJackMoebiusMaster: Bool = false) {
        self.init(name: name, ports: ports, isSystem: isPlayback, bundleID: bundleID, isJackMoebiusMaster: isJackMoebiusMaster)
    }
    /// The sound card: its inputs are the playback ports of the system, shown as "system (playback)".
    public var isPlayback: Bool { isSystem }
    public var displayName: String { isSystem ? "system (playback)" : name }
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
    /// The applications behind the clients (their icons), from the metadata of JACK and from the JackMoebius daemon.
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
        let ports = bridge.getPorts()
        let inputs = ports.filter { $0.direction == .input && $0.type == .audio && $0.clientName != Self.clientName }
        var groups = Self.groupClients(inputPorts: inputs.map(\.id))
        applications.update(clients: Set(groups.filter { !$0.isPlayback }.map(\.name)))
        for i in groups.indices where !groups[i].isPlayback {
            groups[i].bundleID = applications.bundles[groups[i].name]
            groups[i].isJackMoebiusMaster = groups[i].name == ClientApplications.jackMoebiusClient || bridge.isJackMoebiusMaster(name: groups[i].name)
        }
        destinations = groups
        clientNames = Set(ports.map(\.clientName))
        sampleRate = Int(bridge.sampleRate)
        bufferSize = Int(bridge.bufferSize)
        notifyChange()
    }

    /// What a player holds in place of the graph itself: it has its own `onChange`, so that several players (one for each session) can listen to the
    /// one JACK client of the application. It keeps a weak reference to nothing: the graph lets go of a handle that is gone.
    public func makeHandle() -> GraphHandle {
        let handle = GraphHandle(graph: self)
        handles.append(WeakHandle(handle))
        return handle
    }

    fileprivate struct WeakHandle { weak var value: GraphHandle?; init(_ v: GraphHandle) { value = v } }
    @ObservationIgnored fileprivate var handles: [WeakHandle] = []

    func notifyChange() {
        handles.removeAll { $0.value == nil }
        onChange?()
        for handle in handles { handle.value?.onChange?() }
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

    /// The applications behind some clients have been found: their boxes get their icon.
    private func applyApplications() {
        var groups = destinations
        var changed = false
        for i in groups.indices where !groups[i].isPlayback && groups[i].bundleID == nil {
            if let id = applications.bundles[groups[i].name] { groups[i].bundleID = id; changed = true }
        }
        if changed { destinations = groups }
    }

    private func serverStopped() {
        applications.reset()
        bridge.close()
        isConnected = false
        destinations = []
        clientNames = []
        sampleRate = nil
        bufferSize = nil
        notifyChange()
    }

    private func pollServerState() {
        guard bridge.isConnected else { return }
        // JackMoebius may publish the application of a box a little after the box appeared: look again.
        applications.update(clients: Set(destinations.filter { !$0.isPlayback }.map(\.name)))
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
        JackPortClient.group(ports: inputPorts)
    }
}

/// The graph as one player sees it: everything is the graph's, except the call that says it has changed, which is the player's own.
@MainActor
public final class GraphHandle: PlaybackServer {
    private let graph: PlaybackGraph
    public var onChange: (() -> Void)?

    init(graph: PlaybackGraph) { self.graph = graph }

    public var isConnected: Bool { graph.isConnected }
    public var sampleRate: Int? { graph.sampleRate }
    public var bufferSize: Int? { graph.bufferSize }
    public var playbackPorts: [String] { graph.playbackPorts }
    public func transportStart() { graph.transportStart() }
    public func transportPause() { graph.transportPause() }
    public func transportStop() { graph.transportStop() }
    public func transportLocate(frame: UInt32) { graph.transportLocate(frame: frame) }
    public func outputPorts() -> Set<String> { graph.outputPorts() }
    public func inputPorts() -> Set<String> { graph.inputPorts() }
    public func destinations(of output: String) -> Set<String> { graph.destinations(of: output) }
    public func allLinks() -> Set<JackLink> { graph.allLinks() }
    public func connect(from output: String, to input: String) throws { try graph.connect(from: output, to: input) }
    public func disconnect(from output: String, to input: String) throws { try graph.disconnect(from: output, to: input) }
}
