// SPDX-License-Identifier: MIT

import Foundation

/// Which application stands behind each client of a JACK server, so that a window can show its real icon. JackMoebius makes a
/// client for each CoreAudio application it exposes. The application is found in the JACK metadata of the client, else by name in
/// the list of the JackMoebius daemon, which is asked up to three times for a given set of clients (the box of an application may
/// appear in the server a moment before the daemon lists it). Nothing happens when the daemon is not there.
///
/// Shared by the applications of the collection that show the clients of a JACK server. Call `update(clients:)` after each read
/// of the graph (and from the slow poll, which finds metadata published late), and read `bundles`.
@MainActor
public final class ClientApplications {
    /// The client of the JackMoebius system node, whose shared inputs get the picto of JackMoebius.
    public static let jackMoebiusClient = "JackMoebius"

    /// The bundle identifier of the application, by the name of its client.
    public private(set) var bundles: [String: String] = [:]
    /// Called when `bundles` has gained applications.
    public var onChange: (() -> Void)?

    private let metadata: (String) -> String?
    private let daemonKeys: @Sendable () -> [String: String]
    private let daemonIsPresent: () -> Bool
    private let retryDelay: UInt64
    private var clientsSeen: Set<String> = []
    private var attempts = 0
    private var isAsking = false

    /// - Parameters:
    ///   - metadata: the application in the JACK metadata of a client (`JackBridgeWrapper.coreAudioBoxKey(name:)`).
    ///   - retryDelay: nanoseconds, multiplied by the number of the attempt.
    public init(metadata: @escaping (String) -> String?,
                daemonKeys: @escaping @Sendable () -> [String: String] = { JackMoebiusDaemon.applicationKeys() },
                daemonIsPresent: @escaping () -> Bool = { JackMoebiusDaemon.isPresent },
                retryDelay: UInt64 = 400_000_000) {
        self.metadata = metadata
        self.daemonKeys = daemonKeys
        self.daemonIsPresent = daemonIsPresent
        self.retryDelay = retryDelay
    }

    /// The clients of the graph that are not the sound card. The ones whose application is not known yet are looked up.
    public func update(clients: Set<String>) {
        if clients != clientsSeen {
            clientsSeen = clients
            attempts = 0
        }
        var changed = false
        for name in clients where bundles[name] == nil {
            if let id = metadata(name), !id.isEmpty { bundles[name] = id; changed = true }
        }
        if changed { onChange?() }
        askDaemon()
    }

    /// Forgets what was found, when the server has gone.
    public func reset() {
        bundles = [:]
        clientsSeen = []
        attempts = 0
    }

    private var missing: [String] { clientsSeen.filter { bundles[$0] == nil } }

    private func askDaemon() {
        guard !isAsking, attempts < 3, !missing.isEmpty, daemonIsPresent() else { return }
        isAsking = true
        attempts += 1
        let attempt = attempts
        let keysOf = daemonKeys
        Task { [weak self] in
            // The daemon is asked away from the main actor: the socket read can block for a moment.
            let keys = await Task.detached(priority: .utility) { keysOf() }.value
            guard let self else { return }
            self.isAsking = false
            var changed = false
            for name in self.missing {
                if let id = JackMoebiusDaemon.key(forClient: name, in: keys) { self.bundles[name] = id; changed = true }
            }
            if changed { self.onChange?() }
            if !self.missing.isEmpty, self.attempts < 3 {
                try? await Task.sleep(nanoseconds: self.retryDelay * UInt64(attempt))
                self.askDaemon()
            }
        }
    }
}
