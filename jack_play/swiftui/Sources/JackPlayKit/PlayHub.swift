// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Observation

/// Where the output levels are shown: under the waveform, or beside the lane of each channel.
public enum LevelsPlacement: String, Sendable {
    case below, inline
}

/// What the whole application shares, whatever the number of sessions: the JACK client (one, for all the players), the connections remembered for each
/// file, the settings kept between two launches and the numbers of the sessions. Each window has a session: its player, its playlist, its settings.
@MainActor
@Observable
public final class PlayHub {
    /// The JACK graph: where the files can go, state of the server.
    public let graph = PlaybackGraph()
    /// The connections remembered for each file.
    @ObservationIgnored public let store: ConnectionStore
    /// Where the settings are kept between two launches; nil for a run that must not keep them.
    @ObservationIgnored public let defaults: UserDefaults?
    /// Where the levels are shown: a choice of look, the same for every session.
    public var levelsPlacement: LevelsPlacement {
        didSet { if levelsPlacement != oldValue { defaults?.set(levelsPlacement.rawValue, forKey: Self.levelsPlacementKey) } }
    }

    public static let levelsPlacementKey = "levelsPlacement"

    public init(defaults: UserDefaults?) {
        self.defaults = defaults
        store = ConnectionStore(defaults: defaults ?? UserDefaults(suiteName: "jackplay.volatile.\(UUID().uuidString)")!)
        levelsPlacement = defaults?.string(forKey: Self.levelsPlacementKey).flatMap(LevelsPlacement.init(rawValue:)) ?? .inline
    }

    // MARK: The first session

    @ObservationIgnored private var savedStateClaimed = false

    /// The first session of the application starts from the settings and the list of the last one; the others start from the defaults. True once, for the first caller.
    public func claimSavedState() -> Bool {
        defer { savedStateClaimed = true }
        return !savedStateClaimed
    }

    // MARK: The numbers of the sessions

    /// The numbers that sessions hold, from 1. The number is in the names of the JACK clients from the second session on (see `PlayerSettings.programName`).
    @ObservationIgnored private var heldNumbers: Set<Int> = []

    /// The lowest number that no session holds.
    public func takeSessionNumber() -> Int {
        var n = 1
        while heldNumbers.contains(n) { n += 1 }
        heldNumbers.insert(n)
        return n
    }

    /// Gives a number back. It is given back when `isFree` says that the programs of the session have left (a new session with the same number would start
    /// a program of the same name while the old one is still there, and JACK would rename it); the wait is five seconds at most.
    public func releaseSessionNumber(_ number: Int, whenFree isFree: @escaping @MainActor () -> Bool = { true }) {
        Task { [weak self] in
            var waited = 0.0
            while !isFree(), waited < 5 {
                try? await Task.sleep(for: .milliseconds(200))
                waited += 0.2
            }
            self?.heldNumbers.remove(number)
        }
    }
}

/// What a file opened from outside (the Finder, the icon of the Dock) leads to.
public enum OutsideOpenPlan: Equatable, Sendable {
    /// A new session, in a window of its own.
    case newSession
    /// The session in front takes them as its list (it has nothing to lose).
    case useSession
    /// The person is asked: add them to the list of the session in front, or open a new session.
    case ask

    /// - Parameters:
    ///   - hasTarget: a session is in front.
    ///   - isBlank: it has no file and no list.
    ///   - isPlaying: it plays.
    ///   - atLaunch: the application has just started (a file opened from the Finder starts it): the window that comes back with the list of the last time is
    ///     not something to be asked about, the file replaces the list as it always did.
    public static func plan(hasTarget: Bool, isBlank: Bool, isPlaying: Bool, atLaunch: Bool) -> OutsideOpenPlan {
        guard hasTarget else { return .newSession }
        if isBlank || (atLaunch && !isPlaying) { return .useSession }
        return .ask
    }
}
