// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import Observation
import JackBridge

/// A JACK client that has audio outputs: a source for the recording.
public struct JackSourceClient: Identifiable, Equatable, Sendable {
    public var id: String { name }
    public let name: String
    /// Port names without the client part, in the order JACK lists them.
    public var ports: [String]
    /// Its audio input ports, which jack_capture can also use: it takes what is connected to them.
    public var inputs: [String] = []
    /// The hardware capture ports ("system"): shown as "system (capture)".
    public let isCapture: Bool
    /// Bundle identifier of the application a JackMoebius box stands for, if any.
    public var bundleID: String?
    /// A client that was chosen earlier and is not in the graph now: the matrix still lists it, so that it can be unchosen.
    public var isAbsent = false

    public init(name: String, ports: [String], isCapture: Bool, isAbsent: Bool = false) {
        self.name = name
        self.ports = ports
        self.isCapture = isCapture
        self.isAbsent = isAbsent
    }

    public var displayName: String { isCapture ? "system (capture)" : name }
    public func fullName(of port: String) -> String { "\(name):\(port)" }
}

/// The JACK graph as the source matrix needs it: the audio outputs by client, which of them reach
/// the system playback ports, and the state of the server. The application opens one JACK client
/// of its own for this and keeps trying while no server runs.
@MainActor
@Observable
public final class JackGraph {
    public private(set) var isConnected = false
    public private(set) var sampleRate: Int?
    public private(set) var bufferSize: Int?
    public private(set) var clients: [JackSourceClient] = []
    /// Every client of the graph, with ports of any kind: the names that are taken.
    public private(set) var clientNames: Set<String> = []
    /// Outputs ("client:port") connected to the system playback ports: what is heard.
    public private(set) var heardPorts: Set<String> = []
    /// For each audio input port ("client:port"), the outputs connected to it now. A channel fed by an input
    /// port receives these.
    public private(set) var inputConnections: [String: [String]] = [:]
    public private(set) var xruns = 0

    public static let clientName = "JackCapture-UI"

    private let bridge = JackBridgeWrapper()
    private var retry: Task<Void, Never>?
    private var pending: Task<Void, Never>?

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
        let connections = bridge.getConnections()
        let outputs = ports.filter { $0.direction == .output && $0.type == .audio && $0.clientName != Self.clientName }
        let inputs = ports.filter { $0.direction == .input && $0.type == .audio && $0.clientName != Self.clientName }
        var groups = Self.groupClients(outputPorts: outputs.map(\.id), inputPorts: inputs.map(\.id))
        for i in groups.indices where !groups[i].isCapture {
            groups[i].bundleID = bridge.coreAudioBoxKey(name: groups[i].name)
        }
        #if DEBUG
        // Development aid: JACKCAPTURE_FAKEBUNDLE="metro=com.apple.Safari,Other=com.apple.Music" gives clients an application.
        if let spec = ProcessInfo.processInfo.environment["JACKCAPTURE_FAKEBUNDLE"] {
            let map = Dictionary(uniqueKeysWithValues: spec.split(separator: ",").compactMap { pair -> (String, String)? in
                let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
                return kv.count == 2 ? (kv[0], kv[1]) : nil
            })
            for i in groups.indices { if let id = map[groups[i].name] { groups[i].bundleID = id } }
        }
        #endif
        clients = groups
        // A client that has just appeared is looked up at once, not at the next poll.
        daemonAttempts = 0
        askDaemonForApplications()
        clientNames = Set(ports.map(\.clientName))
        heardPorts = Self.heardOutputs(connections: connections.map { ($0.from, $0.to) })
        inputConnections = Self.inputSources(inputPorts: inputs.map(\.id), connections: connections.map { ($0.from, $0.to) })
        sampleRate = Int(bridge.sampleRate)
        bufferSize = Int(bridge.bufferSize)
    }

    /// The JACK transport, for the development aids that drive a recording that waits for it.
    public func setTransportRolling(_ rolling: Bool) {
        if rolling { bridge.transportStart() } else { bridge.transportStop() }
    }

    /// Makes connections, waiting for the ports to exist: a client that has just been started registers them a
    /// little later. Returns the connections that could not be made.
    public func connectWhenReady(_ pairs: [(source: String, destination: String)], timeout: TimeInterval = 5) async -> [String] {
        var failed: [String] = []
        let deadline = Date().addingTimeInterval(timeout)
        for pair in pairs {
            var done = false
            while !done && Date() < deadline {
                do {
                    try bridge.connect(from: pair.source, to: pair.destination, fromType: .audio, toType: .audio)
                    done = true
                } catch {
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
            if !done { failed.append("\(pair.source) → \(pair.destination)") }
        }
        return failed
    }

    private func tryOpen() {
        do {
            try bridge.open(clientName: Self.clientName)
        } catch {
            return
        }
        bridge.onPortRegistration = { [weak self] _, _ in self?.scheduleRefresh() }
        bridge.onPortConnect = { [weak self] _, _ in self?.scheduleRefresh() }
        bridge.onShutdown = { [weak self] in self?.serverStopped() }
        isConnected = true
        refresh()
    }

    private func serverStopped() {
        bridge.close()
        isConnected = false
        clients = []
        clientNames = []
        heardPorts = []
        sampleRate = nil
        bufferSize = nil
    }

    private func pollServerState() {
        guard bridge.isConnected else { return }
        sampleRate = Int(bridge.sampleRate)
        bufferSize = Int(bridge.bufferSize)
        xruns = Int(bridge.xrunCount)
        // JackMoebius may publish the application of a box a little after the box appeared: ask again.
        var found = clients
        var changed = false
        for i in found.indices where found[i].bundleID == nil && !found[i].isCapture {
            if let id = bridge.coreAudioBoxKey(name: found[i].name) { found[i].bundleID = id; changed = true }
        }
        if changed { clients = found }
        askDaemonForApplications()
    }

    private var isAskingDaemon = false
    private var daemonAttempts = 0

    /// The clients whose application is still unknown are looked up in the list of the JackMoebius daemon, by name: the
    /// daemon knows the applications it exposes even where the boxes carry no JACK metadata.
    private func askDaemonForApplications() {
        guard !isAskingDaemon, JackMoebiusDaemon.isPresent,
              clients.contains(where: { $0.bundleID == nil && !$0.isCapture }) else { return }
        isAskingDaemon = true
        Task { [weak self] in
            let keys = await Task.detached(priority: .utility) { JackMoebiusDaemon.applicationKeys() }.value
            guard let self else { return }
            self.isAskingDaemon = false
            var found = self.clients
            var changed = false
            for i in found.indices where found[i].bundleID == nil && !found[i].isCapture {
                if let id = JackMoebiusDaemon.key(forClient: found[i].name, in: keys) { found[i].bundleID = id; changed = true }
            }
            if changed { self.clients = found }
            // The daemon may list a box a moment after its ports appear: a few quick tries before the slow poll.
            if found.contains(where: { $0.bundleID == nil && !$0.isCapture }), self.daemonAttempts < 3 {
                self.daemonAttempts += 1
                try? await Task.sleep(for: .milliseconds(400 * self.daemonAttempts))
                self.askDaemonForApplications()
            }
        }
    }

    /// Port events come in bursts (a client registers all its ports at once): one read for the burst.
    private func scheduleRefresh() {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            if !Task.isCancelled { self?.refresh() }
        }
    }

    // MARK: Pure parts, tested without a server

    /// Groups output ports by client. The capture client comes first, the others by name.
    nonisolated static func groupClients(outputPorts: [String], inputPorts: [String] = []) -> [JackSourceClient] {
        var order: [String] = []
        var ports: [String: [String]] = [:]
        for full in outputPorts {
            guard let colon = full.firstIndex(of: ":") else { continue }
            let client = String(full[..<colon]), port = String(full[full.index(after: colon)...])
            if ports[client] == nil { order.append(client) }
            ports[client, default: []].append(port)
        }
        var inputs: [String: [String]] = [:]
        for full in inputPorts {
            guard let colon = full.firstIndex(of: ":") else { continue }
            inputs[String(full[..<colon]), default: []].append(String(full[full.index(after: colon)...]))
        }
        let groups = order.map { name -> JackSourceClient in
            var client = JackSourceClient(name: name, ports: ports[name] ?? [], isCapture: name == "system")
            client.inputs = inputs[name] ?? []   // only for clients that are already sources
            return client
        }
        return groups.sorted {
            if $0.isCapture != $1.isCapture { return $0.isCapture }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// For every input port, the outputs connected to it (an empty list when nothing is).
    nonisolated static func inputSources(inputPorts: [String], connections: [(from: String, to: String)]) -> [String: [String]] {
        var result = Dictionary(uniqueKeysWithValues: inputPorts.map { ($0, [String]()) })
        for c in connections where result[c.to] != nil { result[c.to]?.append(c.from) }
        return result
    }

    /// The name to give a client: the wanted one, or the wanted one followed by a number when it is taken (JACK
    /// would otherwise rename the client itself, and the connections made by name would reach the other one).
    nonisolated static func freeName(_ wanted: String, taken: Set<String>) -> String {
        guard taken.contains(wanted) else { return wanted }
        var n = 2
        while taken.contains("\(wanted) \(n)") { n += 1 }
        return "\(wanted) \(n)"
    }

    /// Outputs with a connection to a system playback port.
    nonisolated static func heardOutputs(connections: [(from: String, to: String)]) -> Set<String> {
        Set(connections.filter { $0.to.hasPrefix("system:playback_") }.map(\.from))
    }

    /// The system capture ports, in order: the inputs of the sound card.
    public var systemInputs: [String] {
        guard let system = clients.first(where: \.isCapture) else { return [] }
        return system.ports.map { system.fullName(of: $0) }
    }
}
