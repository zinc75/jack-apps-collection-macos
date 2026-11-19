// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// What the application remembers between launches: the settings of each direction and which of them are armed.
public struct StoredBridgeSettings: Codable, Equatable, Sendable {
    public var send = SendSettings()
    public var receive = ReceiveSettings()
    /// Nothing is armed the first time: the window asks what is wanted (receive, send, or both).
    public var sendArmed = false
    public var receiveArmed = false
    public init() {}
}

public final class BridgeSettingsStore {
    public static let defaultsKey = "bridgeSettings"
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// What was saved, or the defaults the first time (or when what was saved cannot be read any more).
    public func load() -> StoredBridgeSettings {
        defaults.data(forKey: Self.defaultsKey).flatMap { try? JSONDecoder().decode(StoredBridgeSettings.self, from: $0) } ?? StoredBridgeSettings()
    }

    public var hasSavedSettings: Bool { defaults.data(forKey: Self.defaultsKey) != nil }

    public func save(_ settings: StoredBridgeSettings) {
        if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: Self.defaultsKey) }
    }
}
