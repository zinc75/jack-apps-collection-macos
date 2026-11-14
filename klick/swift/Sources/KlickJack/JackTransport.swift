// SPDX-License-Identifier: GPL-2.0-or-later
// Licence of the program this interface drives (klick).
import SwiftUI
import CKlickJack
import KlickEngine
import KlickKit
import KlickUI
import AppearanceKit

/// What the JACK transport does to what plays: nothing, waiting for it to roll, or rolling with it; and the tempo and meter of another
/// client that is the timebase master (the simple metronome takes them, a tempo map keeps its own).
public struct TransportInfo: Equatable, Sendable {
    public enum State: Int, Sendable {
        /// Not following (or stopped).
        case off = 0
        /// Following: waits for the transport to roll.
        case waiting = 1
        /// Following: the transport rolls, and what plays plays with it.
        case rolling = 2
    }
    public var state = State.off
    /// Another client is the timebase master; `tempo` (quarter notes per minute), `beats` and `denominator` are its tempo and meter.
    public var hasExternalMaster = false
    public var tempo = 0.0
    public var beats = 4
    public var denominator = 4

    public init(state: State = .off, hasExternalMaster: Bool = false, tempo: Double = 0, beats: Int = 4, denominator: Int = 4) {
        self.state = state; self.hasExternalMaster = hasExternalMaster; self.tempo = tempo; self.beats = beats; self.denominator = denominator
    }
}

/// The functions of the JACK library on an engine that plays on JACK.
extension Engine {
    /// The metronome and the tempo map follow the JACK transport when they start: they play while it rolls (the map at the position of
    /// the transport, the metronome from its first beat, or from the beat of the song when another client is the timebase master),
    /// until they are stopped; there is no count-in. No effect on an engine that does not play on JACK.
    func setTransportFollow(_ follow: Bool) { klick_jack_set_transport_follow(rawHandle, follow ? 1 : 0) }

    /// Becomes the timebase master of the transport (bars, beats and tempo for the other clients), replacing the one there is; or
    /// gives it up. Throws when the master cannot be taken.
    func setTimebaseMaster(_ on: Bool) throws {
        var message = [CChar](repeating: 0, count: 256)
        if klick_jack_set_timebase_master(rawHandle, on ? 1 : 0, &message, message.count) == 0 { throw JackError(message: String(cString: message)) }
    }

    /// What the transport does to the engine (read now and then, from the control thread).
    var transportInfo: TransportInfo {
        var raw = KlickJackTransportInfo()
        klick_jack_transport_info(rawHandle, &raw)
        return TransportInfo(state: TransportInfo.State(rawValue: Int(raw.state)) ?? .off, hasExternalMaster: raw.external != 0,
                             tempo: Double(raw.tempo), beats: Int(raw.beats), denominator: Int(raw.denom))
    }
}

// MARK: what the window shows

/// Says that what plays is driven by the JACK transport: it waits for the transport to roll, or it plays with it. When the transport is
/// followed and nothing waits, it says so too, in the footer.
struct TransportBadge: View {
    @Environment(\.appAccentColor) private var accent
    @Environment(AppModel.self) private var model
    let jack: JackBackend
    let place: BackendStatusPlace

    var body: some View {
        let state = jack.transport.state
        if model.isPlaying, state != .off {
            Label(LocalizedStringKey(state == .rolling ? "Piloté par le transport JACK" : "En attente du transport JACK"),
                  systemImage: state == .rolling ? "link" : "hourglass")
                .font(.caption).fontWeight(.medium)
                .foregroundStyle(state == .rolling ? accent : Color.secondary)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(state == .rolling ? accent.opacity(0.16) : Color.primary.opacity(0.08)))
                .help("Le départ et l'arrêt suivent le transport JACK. Le bouton arrête ; un nouvel appui remet en attente.")
        } else if place == .footer, !model.isPlaying, model.backendStartsByItself {
            Text("Arrêté : le transport JACK n'est pas suivi").font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Another client of JACK is the timebase master: the metronome takes its tempo and meter, a tempo map keeps its own (and says so).
struct ExternalMasterNote: View {
    @Environment(AppModel.self) private var model
    let jack: JackBackend
    let mode: Mode

    var body: some View {
        let info = jack.transport
        if model.isPlaying, info.state != .off, info.hasExternalMaster, model.player.mode == mode {
            Label {
                if mode == .simple {
                    Text("Tempo et mesure du maître de timebase JACK : \(Int(info.tempo.rounded())) BPM, \(info.beats)/\(info.denominator)")
                } else {
                    Text("Un autre client JACK est maître de timebase : la carte garde son tempo, qui peut différer du sien.")
                }
            } icon: {
                Image(systemName: mode == .simple ? "metronome" : "exclamationmark.triangle")
            }
            .font(.caption).foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
    }
}

/// The badge and the note, for one place of the window.
struct TransportStatusView: View {
    @Environment(AppModel.self) private var model
    let place: BackendStatusPlace

    var body: some View {
        if let jack = model.backend as? JackBackend {
            let mode: Mode = place == .map ? .map : (place == .footer ? (model.player.mode ?? model.mode) : .simple)
            VStack(spacing: 6) {
                TransportBadge(jack: jack, place: place)
                ExternalMasterNote(jack: jack, mode: mode)
            }
        }
    }
}
