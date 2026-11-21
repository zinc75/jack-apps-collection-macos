// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import JackBridge
import Observation

/// The state of the JACK server as the application shows it: whether it runs, its rate and its period, and the audio cuts
/// (xruns). The application opens a JACK client of its own for this and keeps trying while no server runs.
@MainActor
@Observable
public final class JackStatus {
    public private(set) var isConnected = false
    public private(set) var sampleRate: Int?
    /// The JACK period, in frames.
    public private(set) var bufferSize: Int?
    /// The xruns since the application connected.
    public private(set) var xrunCount = 0

    public static let clientName = "JackConvolver-UI"

    /// Called with the number of xruns that came since the last reading.
    @ObservationIgnored public var onXruns: ((Int) -> Void)?
    @ObservationIgnored private let bridge = JackBridgeWrapper()
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var lastXruns: UInt32 = 0

    public init() {}

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
        bridge.close()
        isConnected = false
        sampleRate = nil
        bufferSize = nil
    }

    private func tryOpen() {
        do { try bridge.open(clientName: Self.clientName) } catch { return }
        bridge.onShutdown = { [weak self] in Task { @MainActor in self?.serverStopped() } }
        bridge.resetXrunCount()
        lastXruns = 0
        isConnected = true
        poll()
    }

    private func serverStopped() {
        bridge.close()
        isConnected = false
        sampleRate = nil
        bufferSize = nil
    }

    private func poll() {
        guard bridge.isConnected else { serverStopped(); return }
        sampleRate = Int(bridge.sampleRate)
        let frames = Int(bridge.bufferSize)
        bufferSize = frames > 0 ? frames : nil
        let count = bridge.xrunCount
        if count > lastXruns {
            let new = Int(count - lastXruns)
            lastXruns = count
            xrunCount += new
            onXruns?(new)
        }
    }
}
