// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import JackBridge

/// A JACK client of its own that listens to the chosen sources while nothing is recorded, so that their levels can be shown
/// before the red button is pressed. It has one input port per channel ("in1", "in2", …), connected to the sources of that
/// channel, and measures their peaks in its process callback. It is a client apart from the one of the graph: opening
/// and closing it leaves the other alone.
@MainActor
final class LevelMonitor {
    /// What the client listens to: the number of channels and, for each, the ports connected to it.
    struct Setup: Equatable {
        var channels: Int
        var links: [Link]
        struct Link: Equatable { var source: String; var channel: Int }
    }

    private var bridge: JackBridgeWrapper?
    private(set) var setup: Setup?
    /// The name JACK gave the client.
    private(set) var clientName: String?

    var isRunning: Bool { bridge?.isConnected ?? false }

    /// Opens the client under `name` and connects it. False when JACK refuses (no server, no port).
    func start(name: String, setup: Setup) -> Bool {
        stop()
        let bridge = JackBridgeWrapper()
        do { try bridge.open(clientName: name) } catch { return false }
        guard bridge.registerMeterPorts(count: setup.channels) == setup.channels, let actual = bridge.clientName else {
            bridge.close()
            return false
        }
        for link in setup.links {
            // A source that is gone, or a port that refuses, leaves its channel silent: nothing else to do.
            try? bridge.connect(from: link.source, to: "\(actual):in\(link.channel + 1)", fromType: .audio, toType: .audio)
        }
        self.bridge = bridge
        self.setup = setup
        clientName = actual
        return true
    }

    func stop() {
        bridge?.close()
        bridge = nil
        setup = nil
        clientName = nil
    }

    /// The peak of each channel since the last call; nil when nothing runs.
    func readPeaks() -> [Float]? {
        guard let bridge, let setup, bridge.isConnected else { return nil }
        return (0..<setup.channels).map { bridge.takeMeterPeak(channel: $0) ?? 0 }
    }
}
