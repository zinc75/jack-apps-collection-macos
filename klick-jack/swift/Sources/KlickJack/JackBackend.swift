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
/// libjack is loaded when needed; no server is ever started.
@MainActor
@Observable
public final class JackBackend: AudioBackend {
    public let id = "jack"
    public let name = "JACK"

    /// The shared input of JackMoebius (the system box that CoreAudio applications play into): JackMate shows the picto of JackMoebius for it.
    public static let jackMoebiusClient = "JackMoebius"

    /// The name Klick gives itself in the server (JACK renames it if it is taken).
    public static let clientName = "Klick"
    /// The setting of the connection at start (`ClickSettings.backendOptions`, backend "jack"): on unless it is "0".
    public static let autoconnectKey = "autoconnect"

    /// The input ports of the server, read again by `refresh`.
    public private(set) var ports: [JackPort] = []
    /// The name of the output port of Klick in the server ("Klick:out"), known once the engine is made.
    public private(set) var portName = ""

    /// The application behind each client of the server (its bundle identifier), for the real icon instead of two letters. The
    /// JackMoebius daemon knows it for the CoreAudio applications it exposes; read again as clients appear.
    public private(set) var bundles: [String: String] = [:]

    @ObservationIgnored private var pendingAutoconnect = false
    @ObservationIgnored private var shutdownReported = false
    @ObservationIgnored private var askingDaemon = false
    @ObservationIgnored private var daemonAttempts = 0
    @ObservationIgnored private var clientsSeen: Set<String> = []

    public init() {}

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
        shutdownReported = false
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
        let name = Self.text { klick_jack_port_name(handle, $0, $1) }
        if name != portName { portName = name }
        if player.isBackendShutdown, !shutdownReported {
            shutdownReported = true
            host.errorMessage = String(localized: "Le serveur JACK s'est arrêté.")
        }
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

    /// Asks the daemon which application stands behind the clients that have none yet: up to three times for a set of clients (the
    /// box of an application may appear in the server a moment before the daemon lists it). The daemon is asked away from the main
    /// actor; nothing happens when it is not there.
    private func resolveBundles() {
        let clients = Set(ports.filter { !$0.isPhysical }.map(\.client))
        if clients != clientsSeen {
            clientsSeen = clients
            daemonAttempts = 0
        }
        let missing = clients.filter { bundles[$0] == nil }
        guard !askingDaemon, !missing.isEmpty, daemonAttempts < 3, JackMoebiusDaemon.isPresent else { return }
        askingDaemon = true
        daemonAttempts += 1
        Task { [weak self] in
            let keys = await Task.detached(priority: .utility) { JackMoebiusDaemon.applicationKeys() }.value
            guard let self else { return }
            askingDaemon = false
            var found = bundles
            for name in missing { if let id = JackMoebiusDaemon.key(forClient: name, in: keys) { found[name] = id } }
            if found != bundles { bundles = found }
        }
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
