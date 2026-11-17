// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The options of `jack_play` that the application lets the person change.
public struct PlayerSettings: Equatable, Sendable {
    /// The resampling algorithm of libsamplerate (`-c`): 0 best, 1 medium, 2 fastest, 3 zero order hold, 4 linear.
    public var converter: Int
    /// The ring buffer, in frames (`-b`).
    public var bufferFrames: Int
    /// The name of the JACK client (`-n`); the program adds its process number to it.
    public var clientName: String
    /// Play the file again and again, without a gap (`-l`).
    public var loop: Bool

    public static let converters = [0, 1, 2, 3, 4]
    public static let bufferSizes = [1024, 2048, 4096, 8192, 16384, 32768]

    public init(converter: Int = 0, bufferFrames: Int = 4096, clientName: String = "jack_play", loop: Bool = false) {
        self.converter = converter
        self.bufferFrames = bufferFrames
        self.clientName = clientName
        self.loop = loop
    }

    /// The name of the program that plays the file at a place of the playlist: the place and the size of the list, then the name
    /// chosen, "02 of 12 - jack_play". Without a number, the name chosen.
    /// The programs of two files that follow each other are alive together for a moment, so their names must differ (JACK would
    /// call the second one "name-01"), and the place in the list makes each name its own.
    /// The place comes first on purpose: JACK on macOS names the semaphore of a client "js<uid>.<server><client>" and cuts it at
    /// 31 characters (the server is left out when it is "default"), so two clients whose names are the same up to there cannot
    /// live together. With the place at the start, the names differ whatever the name chosen and the name of the server.
    /// The words are the same in every language: it is a name in JACK, and patchbays remember connections by name.
    public func programName(number: Int?, of count: Int? = nil) -> String {
        guard let number else { return safeClientName }
        let place = count.map { String(format: "%02d of %02d", number, $0) } ?? String(format: "%02d", number)
        return place + " - " + String(safeClientName.prefix(44)).trimmingCharacters(in: .whitespaces)
    }

    /// A name JACK accepts: the characters it does not like are replaced, and it is not empty.
    public var safeClientName: String {
        let cleaned = clientName.map { $0.isLetter || $0.isNumber || "-_. ()".contains($0) ? $0 : "_" }
        let name = String(cleaned).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "jack_play" : String(name.prefix(48))
    }
}

/// How `jack_play` is started to play a file for the application.
public struct PlayerCommand: Equatable, Sendable {
    /// Who decides when the file plays.
    public enum Mode: Equatable, Sendable {
        /// The application: `-C`, the program starts paused and obeys play, pause and seek.
        case independent
        /// The JACK transport, which every client of the server shares: `-t`. The application only watches (`-M`).
        case followTransport
    }

    public var file: URL
    public var settings: PlayerSettings
    public var mode: Mode
    /// Where to start in the file, in frames of the file; nil for the beginning.
    public var initialFrame: Int64?
    /// The period of the JACK server, in frames, when it is known.
    public var serverPeriod: Int?
    /// The sample rate of the file, when it is known.
    public var fileRate: Double?

    public init(file: URL, settings: PlayerSettings = PlayerSettings(), mode: Mode = .independent, initialFrame: Int64? = nil,
                serverPeriod: Int? = nil, fileRate: Double? = nil) {
        self.serverPeriod = serverPeriod
        self.fileRate = fileRate
        self.file = file
        self.settings = settings
        self.mode = mode
        self.initialFrame = initialFrame
    }

    /// The ring buffer the program is given. It stops with an error when the buffer is not larger than a period of the
    /// server, and a buffer of two periods leaves it no margin: it is at least four periods.
    /// It also holds at least a tenth of a second of the file: the program says when the file will end once it has read it all,
    /// which is a ring buffer ahead of the end, and the program of the next file must be told in time (a file at 192 kHz has
    /// only 21 ms in 4096 frames).
    public var bufferFrames: Int { max(settings.bufferFrames, 4 * (serverPeriod ?? 0), Int((fileRate ?? 0) / 10)) }

    /// The arguments given to the program. Both modes make it say where it is and how loud it is on its standard
    /// output (`-C` includes `-M`).
    public var arguments: [String] {
        var a = [mode == .independent ? "-C" : "-t", "-u", "-n", settings.safeClientName, "-c", String(settings.converter), "-b", String(bufferFrames)]
        if mode == .followTransport { a.append("-M") }
        // The program does not loop when it follows the transport: the option is left out rather than shown for nothing.
        if settings.loop, mode == .independent { a.append("-l") }
        if let initialFrame, initialFrame > 0 { a += ["-i", String(initialFrame)] }
        // The path of a file is absolute, so it never starts with a dash: it cannot be taken for an option.
        a.append(file.path)
        return a
    }

    /// The same command as a person would type it in the Terminal, for the "command line" sheet.
    public func display(program: String = "jack_play") -> String {
        ([program] + arguments.map(Self.quote)).joined(separator: " ")
    }

    /// A word of a shell command, quoted when it needs to be.
    static func quote(_ word: String) -> String {
        guard !word.isEmpty else { return "''" }
        let safe = word.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_./=:@%+,".contains($0)) }
        return safe ? word : "'" + word.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// What the application asks `jack_play` to do.
public enum PlayerControl: Equatable, Sendable {
    case play
    /// Play from the beginning of the cycle in which this time of JACK comes (see `PlayerEvent.endAnnounced`).
    case playAt(UInt32)
    case pause
    /// A frame of the file (not of the server).
    case seek(Int64)
    case quit

    /// The line sent to the standard input of the program.
    public var line: String {
        switch self {
        case .play: return "play"
        case .playAt(let time): return "play at \(time)"
        case .pause: return "pause"
        case .seek(let frame): return "seek \(max(frame, 0))"
        case .quit: return "quit"
        }
    }
}
