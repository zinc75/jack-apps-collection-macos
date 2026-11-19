// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Observation
import SwiftUI
import ZitaBridgeKit

enum Page: String, CaseIterable, Identifiable {
    case link, network, lanes, flow, display
    var id: String { rawValue }
}

/// What the window needs: the controller of the link, and the page that is shown.
@MainActor
@Observable
final class AppModel {
    let controller: BridgeController
    var page = Page.link
    /// The direction whose start button is to be shown (it flashes), and a count that tells each time to flash again.
    var flashedDirection: LinkDirection?
    var flashCount = 0

    /// Makes the start button of a direction flash, to show where it is: what a link in a text of the page asks for.
    func flash(_ direction: LinkDirection) {
        flashedDirection = direction
        flashCount += 1
    }

    /// - Parameter defaults: where the settings are kept; nil for a throw-away store (the debug aids use it: they must not touch
    ///   what the person has set up).
    init(defaults: UserDefaults?) {
        let store = defaults ?? UserDefaults(suiteName: "zita.debug.\(UUID().uuidString)") ?? .standard
        var server: String?
        #if DEBUG
        server = ProcessInfo.processInfo.environment["ZITABRIDGE_JACKSERVER"]
        #endif
        controller = BridgeController(settingsStore: BridgeSettingsStore(defaults: store), wiringStore: WiringStore(defaults: store), jackServer: server)
        #if DEBUG
        applyDebugAids()
        #endif
    }

    func start() { controller.start() }

    func shutdown() {
        controller.saveSettings()
        controller.shutdown()
    }

    /// What is armed has to be set up before it can start: an address is needed. The round button then says so.
    var needsConfiguration: Bool {
        controller.armedDirections.contains { direction in
            switch direction {
            case .receive: !controller.receiver.settings.issues.isEmpty || controller.receiver.addressNotFound
            case .send: !controller.sender.settings.issues.isEmpty || controller.sender.addressNotFound
            }
        }
    }

    /// The least advanced state of the directions that run: what the round button shows.
    var aggregateState: LinkState {
        let running = controller.armedDirections.map { state(of: $0) }.filter(\.isRunning)
        guard !running.isEmpty else { return .stopped }
        func rank(_ s: LinkState) -> Int { s == .waiting ? 0 : s == .syncing ? 1 : 2 }
        return running.min { rank($0) < rank($1) } ?? .stopped
    }

    func state(of direction: LinkDirection) -> LinkState {
        direction == .receive ? controller.receiver.state : controller.sender.state
    }

    #if DEBUG
    /// Development aids, only in debug builds. They need not touch the settings of the person (the store is a throw-away one):
    /// ZITABRIDGE_DEMO sets both directions to a loopback link on port 19999, ZITABRIDGE_AUTOSTART starts it.
    private func applyDebugAids() {
        let env = ProcessInfo.processInfo.environment
        if env["ZITABRIDGE_DEMO"] != nil {
            controller.receiver.settings.address = "127.0.0.1"; controller.receiver.settings.port = 19999
            controller.sender.settings.address = "127.0.0.1"; controller.sender.settings.port = 19999
            controller.receiveArmed = true; controller.sendArmed = true
        }
        if let list = env["ZITABRIDGE_RECV_CHANNELS"].flatMap(ChannelList.parse) { controller.receiver.settings.automaticChannels = false; controller.receiver.settings.channels = list }
        if let address = env["ZITABRIDGE_SENDADDR"] { controller.sender.settings.address = address }
        if let arm = env["ZITABRIDGE_ARM"] {
            controller.receiveArmed = arm.contains("r"); controller.sendArmed = arm.contains("s")
        }
    }
    #endif
}
