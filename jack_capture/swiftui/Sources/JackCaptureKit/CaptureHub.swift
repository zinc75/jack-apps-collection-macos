// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import Observation

/// What the whole application shares, whatever the number of recordings in progress: the JACK client (one, for all of them), and the settings that are kept
/// between two launches. Each window has a session (`RecorderModel`): its settings, its recording, its page.
@MainActor
@Observable
public final class CaptureHub {
    /// The JACK graph: sources for the matrix, state of the server.
    public let graph = JackGraph()

    /// False on the very first launch, until the page of the channels has been seen: the red button then leads there instead of recording with settings
    /// nobody has looked at.
    public private(set) var isConfigured = true

    /// Where the settings are kept between two launches; nil in the tests.
    @ObservationIgnored let defaults: UserDefaults?
    private static let settingsKey = "settings.v1"
    private static let configuredKey = "configured.v1"

    /// With `defaults`, the settings of the last session are read back by `savedSettings()` and `save(_:)` keeps them.
    public init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
        isConfigured = defaults == nil || defaults?.data(forKey: Self.settingsKey) != nil || defaults?.bool(forKey: Self.configuredKey) == true
    }

    @ObservationIgnored private var savedSettingsClaimed = false

    /// The first session of the application starts from the settings of the last one; the others start from the defaults. True once, for the first caller.
    public func claimSavedSettings() -> Bool {
        defer { savedSettingsClaimed = true }
        return !savedSettingsClaimed
    }

    /// The settings of the last session, brought back inside the limits that may have changed since another version wrote them; nil when nothing is saved.
    public func savedSettings() -> CaptureSettings? {
        guard let data = defaults?.data(forKey: Self.settingsKey), var saved = RecorderModel.decodeSettings(data) else { return nil }
        saved.setFormat(saved.format)
        saved.setChannels(saved.channels)
        return saved
    }

    /// Keeps the settings for the next launch. The session that changed them last is the one that is kept.
    public func save(_ settings: CaptureSettings) {
        guard let defaults, let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.settingsKey)
    }

    /// The page of the channels has been seen: from now on the red button records.
    public func markConfigured() {
        guard !isConfigured else { return }
        isConfigured = true
        defaults?.set(true, forKey: Self.configuredKey)
    }

    #if DEBUG
    /// Development aid: behaves as on a first launch, without touching what is saved.
    public func pretendFirstLaunch() { isConfigured = false }
    #endif
}
