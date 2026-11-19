// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Observation

/// The whole of the link, as the window sees it: the JACK graph, the two directions with their programs, their wiring and
/// their settings. It starts and stops the programs, wires their ports as soon as they exist, and remembers what the person
/// set up.
@MainActor
@Observable
public final class BridgeController {
    public let graph: JackGraph
    public let receiver: ReceiverModel
    public let sender: SenderModel
    /// Where each channel is wired, by direction; kept between launches.
    public private(set) var receiveWiring: ChannelWiring
    public private(set) var sendWiring: ChannelWiring
    /// Which directions the round button starts and stops. Disarming a direction that runs stops it.
    public var receiveArmed: Bool { didSet { if !receiveArmed { stop(.receive) } } }
    public var sendArmed: Bool { didSet { if !sendArmed { stop(.send) } } }

    @ObservationIgnored private let settingsStore: BridgeSettingsStore
    @ObservationIgnored private let wiringStore: WiringStore
    @ObservationIgnored private let receiving: WiringManager
    @ObservationIgnored private let sending: WiringManager
    @ObservationIgnored private var pendingRestart = Set<LinkDirection>()
    @ObservationIgnored private var observing = false

    /// - Parameters:
    ///   - helper: where a program is; the application gives the copies it carries.
    ///   - jackServer: the name of the JACK server (`--jserv`) for the programs; nil for the default one.
    public init(settingsStore: BridgeSettingsStore = BridgeSettingsStore(), wiringStore: WiringStore = WiringStore(),
                helper: (BridgeCommand.Program) -> URL? = { BridgeHelper.executableURL(for: $0) }, jackServer: String? = nil) {
        let stored = settingsStore.load()
        self.settingsStore = settingsStore
        self.wiringStore = wiringStore
        graph = JackGraph()
        receiver = ReceiverModel(settings: stored.receive, executable: helper(.receiver), jackServer: jackServer)
        sender = SenderModel(settings: stored.send, executable: helper(.sender), jackServer: jackServer)
        receiveArmed = stored.receiveArmed
        sendArmed = stored.sendArmed
        receiveWiring = wiringStore.wiring(for: .receive) ?? .empty
        sendWiring = wiringStore.wiring(for: .send) ?? .empty
        receiving = WiringManager(direction: .receive, linking: graph)
        sending = WiringManager(direction: .send, linking: graph)

        graph.onChange = { [weak self] in self?.graphChanged() }
        receiver.onStateChange = { [weak self] in self?.stateChanged(.receive, $0) }
        sender.onStateChange = { [weak self] in self?.stateChanged(.send, $0) }
    }

    // MARK: Running

    /// Connects to the JACK server and starts remembering what changes. Does not start the link.
    public func start() {
        refreshExcludedClients()
        graph.start()
        observeSettings()
    }

    /// The application quits: the programs are stopped (they would end anyway when the application is gone).
    public func shutdown() {
        stop(.receive); stop(.send)
        graph.stop()
    }

    public func isRunning(_ direction: LinkDirection) -> Bool {
        switch direction {
        case .receive: receiver.state.isRunning
        case .send: sender.state.isRunning
        }
    }

    public func isArmed(_ direction: LinkDirection) -> Bool { direction == .receive ? receiveArmed : sendArmed }
    public var armedDirections: [LinkDirection] { [LinkDirection.receive, .send].filter(isArmed) }
    /// Whether the round button would start or stop: something armed runs.
    public var anyArmedRuns: Bool { armedDirections.contains(where: isRunning) }

    /// The round button: starts what is armed, or stops it all when something runs.
    public func toggleAll() {
        let armed = armedDirections
        guard !armed.isEmpty else { return }
        if anyArmedRuns { armed.forEach(stop) } else { armed.forEach(start) }
    }

    public func start(_ direction: LinkDirection) {
        refreshExcludedClients()
        switch direction {
        case .receive: receiver.start()
        case .send: sender.start()
        }
    }

    public func stop(_ direction: LinkDirection) {
        switch direction {
        case .receive: receiver.stop()
        case .send: sender.stop()
        }
    }

    /// Whether the program runs with settings that are not the ones now.
    public func needsRestart(_ direction: LinkDirection) -> Bool {
        direction == .receive ? receiver.needsRestart : sender.needsRestart
    }

    /// Stops the program and starts it again with the settings now; starts it if it does not run.
    public func restart(_ direction: LinkDirection) {
        guard isRunning(direction) else { start(direction); return }
        pendingRestart.insert(direction)
        stop(direction)
    }

    // MARK: Wiring

    public func wiring(for direction: LinkDirection) -> ChannelWiring { direction == .receive ? receiveWiring : sendWiring }

    /// The channels of a direction as they are set now (what the matrix shows).
    public func channels(for direction: LinkDirection) -> [Int] {
        direction == .receive ? receiver.settings.channels : Array(1...max(1, sender.settings.channels))
    }

    public func toggleWire(_ direction: LinkDirection, channel: Int, port: String) {
        var w = wiring(for: direction)
        w.toggle(channel: channel, port: port)
        set(w, for: direction)
    }

    public func clearWiring(_ direction: LinkDirection) { set(.empty, for: direction) }

    /// Wires the channels to the first ports of the sound card, in order.
    public func wireToSoundCard(_ direction: LinkDirection) {
        let ports = direction == .receive ? graph.playbackPorts : graph.capturePorts
        set(DefaultWiring.make(channels: channels(for: direction), systemPorts: ports), for: direction)
    }

    private func set(_ wiring: ChannelWiring, for direction: LinkDirection) {
        switch direction {
        case .receive: receiveWiring = wiring; receiving.update(wiring: wiring)
        case .send: sendWiring = wiring; sending.update(wiring: wiring)
        }
        wiringStore.remember(wiring, for: direction)
    }

    // MARK: What the model and the graph say

    private func stateChanged(_ direction: LinkDirection, _ state: LinkState) {
        let manager = direction == .receive ? receiving : sending
        if state.isRunning {
            // Its ports exist, or will in a moment: the manager waits for them.
            let (client, channels): (String, [Int]) = direction == .receive
                ? (receiver.runningSettings?.clientName ?? receiver.settings.clientName, receiver.runningSettings?.channels ?? receiver.settings.channels)
                : (sender.runningSettings?.clientName ?? sender.settings.clientName, Array(1...max(1, sender.runningSettings?.channels ?? sender.settings.channels)))
            manager.attach(client: client, channels: channels, wiring: wiring(for: direction))
        } else {
            manager.detach()
            if pendingRestart.remove(direction) != nil { start(direction) }
        }
    }

    private func graphChanged() {
        receiving.graphChanged()
        sending.graphChanged()
        applyDefaultWiringTheFirstTime()
    }

    /// The first time, before the person has wired anything, each direction goes to the sound card.
    private func applyDefaultWiringTheFirstTime() {
        if wiringStore.wiring(for: .send) == nil, !graph.capturePorts.isEmpty { wireToSoundCard(.send) }
        if wiringStore.wiring(for: .receive) == nil, !graph.playbackPorts.isEmpty { wireToSoundCard(.receive) }
    }

    /// The programs' own ports are not offered as somewhere to wire to.
    private func refreshExcludedClients() {
        graph.excludedClients = [receiver.settings.clientName, sender.settings.clientName]
    }

    // MARK: Remembering

    private var current: StoredBridgeSettings {
        var s = StoredBridgeSettings()
        s.send = sender.settings; s.receive = receiver.settings
        s.sendArmed = sendArmed; s.receiveArmed = receiveArmed
        return s
    }

    /// Saves what the person sets up, each time it changes.
    private func observeSettings() {
        guard !observing else { return }
        observing = true
        track()
    }

    private func track() {
        withObservationTracking {
            _ = receiver.settings; _ = sender.settings; _ = receiveArmed; _ = sendArmed
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.settingsStore.save(self.current)
                self.refreshExcludedClients()
                self.track()
            }
        }
    }

    /// Saves now (the application is about to quit).
    public func saveSettings() { settingsStore.save(current) }
}
