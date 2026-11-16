// SPDX-License-Identifier: GPL-2.0-or-later
// Licence of the program this interface drives (klick).
import Foundation
import Observation
import JackBridge
import CKlickEngine
import CKlickJack
import KlickEngine
import KlickKit

/// Why the JACK backend could not be used, in the words the user reads.
struct JackError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// The JACK server as an output: Klick is a client of the server, with one output port that is connected to the ports the user chooses.
/// libjack is loaded when needed; no server is ever started. When the server stops, the model falls back on the first backend (AppModel).
@MainActor
@Observable
public final class JackBackend: AudioBackend {
    public let id = "jack"
    public let name = "JACK"

    /// The shared input of JackMoebius (the system box that CoreAudio applications play into): JackMate shows the picto of JackMoebius for it.
    public static let jackMoebiusClient = ClientApplications.jackMoebiusClient

    /// The name Klick gives itself in the server (JACK renames it if it is taken).
    public static let clientName = "Klick"
    /// The setting of the connection at start (`ClickSettings.backendOptions`, backend "jack"): on unless it is "0".
    public static let autoconnectKey = "autoconnect"
    /// The setting of the transport (backend "jack"): "1" when a tempo map follows the transport of JACK; off unless it is "1".
    public static let transportKey = "transport"
    /// The setting "timebase" (backend "jack"): "1" when Klick is the timebase master of the transport (bars, beats, tempo).
    public static let timebaseKey = "timebase"

    /// The input ports of the server, read again by `refresh`.
    public private(set) var ports: [JackPort] = []
    /// The name of the output port of Klick in the server ("Klick:out"), known once the engine is made.
    public private(set) var portName = ""

    /// The application behind each client of the server (its bundle identifier), for the real icon instead of two letters. The
    /// JackMoebius daemon knows it for the CoreAudio applications it exposes; read again as clients appear.
    public private(set) var bundles: [String: String] = [:]

    /// What the JACK transport does to what plays, read at each turn of the display loop of the player.
    public private(set) var transport = TransportInfo()

    @ObservationIgnored private var pendingAutoconnect = false
    /// Finds the application behind each client: Klick reads no JACK metadata, so only the JackMoebius daemon is asked.
    @ObservationIgnored private let applications = ClientApplications(metadata: { _ in nil })

    public init() {
        applications.onChange = { [weak self] in
            guard let self else { return }
            bundles = applications.bundles
        }
    }

    /// The name of the server: the one JACK_DEFAULT_SERVER gives, else the default one.
    public static var serverName: String { ProcessInfo.processInfo.environment["JACK_DEFAULT_SERVER"] ?? "default" }

    public var availability: BackendAvailability {
        var reason = [CChar](repeating: 0, count: 256)
        return klick_jack_available(&reason, reason.count) == 1 ? .available : .unavailable(String(localized: "libjack est introuvable : installez JACK."))
    }

    public func makeEngine() throws -> Engine {
        var backend = KlickBackend()
        var error = [CChar](repeating: 0, count: 256)
        guard klick_jack_backend(Self.clientName, &backend, &error, error.count) != 0 else {
            let message = String(cString: error)
            throw JackError(message: message.contains("not running") ? String(localized: "Le serveur JACK n'est pas démarré.") : message)
        }
        let engine = try Engine(backend: backend)
        pendingAutoconnect = true
        timebaseApplied = false
        ports = []
        return engine
    }

    /// Connects at start when asked to, reads the ports and what the server says of the output. A server that has stopped is reported once.
    public func refresh(player: Player, host: BackendHost) -> OutputInfo? {
        let handle = player.engine.rawHandle
        guard klick_jack_engine(handle) == 1 else { return nil }
        if pendingAutoconnect {
            pendingAutoconnect = false
            if Self.autoconnects(host.settings) { _ = klick_jack_autoconnect(handle) }
        }
        let list = Self.portList(handle)
        if list != ports { ports = list }
        resolveBundles()
        #if DEBUG
        // Development aid: KLICK_FOLLOW=1 turns the following of the transport on (nothing is kept with KLICK_FRESH=1).
        if !debugOptionsApplied, ProcessInfo.processInfo.environment["KLICK_FOLLOW"] != nil {
            debugOptionsApplied = true
            host.settings.setOption(Self.transportKey, "1", backend: "jack")
        }
        #endif
        player.engine.setTransportFollow(Self.followsTransport(host.settings))   // read by the engine when it starts
        if player.didUpdate == nil { player.didUpdate = { [weak self, weak player] in if let self, let player { self.readTransport(player) } } }
        let master = Self.isTimebaseMaster(host.settings)
        if master != timebaseApplied {   // once for each engine (the engine is new after a change of backend or of server)
            timebaseApplied = master
            do { try player.engine.setTimebaseMaster(master) } catch {
                host.errorMessage = error.localizedDescription
                host.settings.setOption(Self.timebaseKey, nil, backend: "jack")
                timebaseApplied = false
            }
        }
        let name = Self.text { klick_jack_port_name(handle, $0, $1) }
        if name != portName { portName = name }
        var info = OutputInfo()
        info.name = Self.serverName
        info.sampleRate = Double(player.sampleRate)
        info.bufferFrames = Int(klick_jack_buffer_size(handle))
        var lmin: UInt32 = 0, lmax: UInt32 = 0
        if klick_jack_playback_latency(handle, &lmin, &lmax) == 1 { info.latencyFrames = Int(lmax) }
        return info
    }

    /// The delay of the display is kept per server, not per device: the latency belongs to the server.
    public func displayOffsetKey(for info: OutputInfo) -> String { "jack:" + info.name }

    // MARK: what the user does

    /// True unless the connection at start was turned off.
    public static func autoconnects(_ settings: ClickSettings) -> Bool { settings.option(autoconnectKey, backend: "jack") != "0" }

    /// True when a tempo map follows the transport of JACK (off unless it was turned on).
    public static func followsTransport(_ settings: ClickSettings) -> Bool { settings.option(transportKey, backend: "jack") == "1" }

    /// True when Klick is to be the timebase master of the transport (off unless it was turned on).
    public static func isTimebaseMaster(_ settings: ClickSettings) -> Bool { settings.option(timebaseKey, backend: "jack") == "1" }

    /// What the engine was told about the timebase master since it was made.
    private var timebaseApplied = false
    #if DEBUG
    private var debugOptionsApplied = false
    #endif

    public func startsByItself(_ settings: ClickSettings) -> Bool { Self.followsTransport(settings) }

    /// The tempo of another client that is the timebase master, while the metronome follows the transport and takes it.
    public var imposedTempo: Double? { transport.state != .off && transport.hasExternalMaster ? transport.tempo : nil }

    /// Reads the transport into `transport`, when it changed: the player calls it at each turn of its display loop, and when it stops.
    func readTransport(_ player: Player) {
        let info = player.isPlaying ? player.engine.transportInfo : TransportInfo()
        if info != transport { transport = info }
    }

    /// Turns the following of the transport on or off: the metronome waits for the transport, and plays with it.
    public func setFollowsTransport(_ on: Bool, model: AppModel) {
        model.settings.setOption(Self.transportKey, on ? "1" : nil, backend: "jack")
        model.player.engine.setTransportFollow(on)
        model.startModeChanged()
    }

    /// Becomes the timebase master of the transport, replacing the one there is (as klick does), or gives it up.
    public func setTimebaseMaster(_ on: Bool, model: AppModel) {
        do {
            try model.player.engine.setTimebaseMaster(on)
            timebaseApplied = on
            model.settings.setOption(Self.timebaseKey, on ? "1" : nil, backend: "jack")
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    /// Turns the connection at start on or off; on, it connects to the first two outputs of the hardware at once.
    public func setAutoconnect(_ on: Bool, model: AppModel) {
        model.settings.setOption(Self.autoconnectKey, on ? nil : "0", backend: "jack")
        if on {
            _ = klick_jack_autoconnect(model.player.engine.rawHandle)
            model.refreshOutput()
        }
    }

    /// Connects the output of Klick to a port, or disconnects it. Returns why it failed, `nil` when it worked.
    @discardableResult
    public func setConnected(_ port: String, _ connected: Bool, player: Player) -> String? {
        var error = [CChar](repeating: 0, count: 256)
        let handle = player.engine.rawHandle
        let ok = connected ? klick_jack_connect(handle, port, &error, error.count) : klick_jack_disconnect(handle, port, &error, error.count)
        if ok == 0 { return String(cString: error) }
        ports = Self.portList(handle)
        return nil
    }

    // MARK: the applications behind the clients

    /// The clients that are not the sound card: the daemon is asked which application stands behind the ones that have none yet.
    private func resolveBundles() {
        applications.update(clients: Set(ports.filter { !$0.isPhysical }.map(\.client)))
    }

    // MARK: reading the C interface

    private static func portList(_ handle: OpaquePointer) -> [JackPort] {
        JackPort.parse(text { klick_jack_list_ports(handle, $0, $1) })
    }

    /// A text of the C interface: it tells how long the whole text is, so a buffer that is too small is made larger.
    private static func text(_ read: (UnsafeMutablePointer<CChar>, Int) -> Int) -> String {
        var size = 4096
        while true {
            var buffer = [CChar](repeating: 0, count: size)
            let needed = read(&buffer, size)
            if needed < size { return String(cString: buffer) }
            size = needed + 1
        }
    }
}
