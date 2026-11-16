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

    /// A name JACK accepts: the characters it does not like are replaced, and it is not empty.
    public var safeClientName: String {
        let cleaned = clientName.map { $0.isLetter || $0.isNumber || "-_. ".contains($0) ? $0 : "_" }
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

    public init(file: URL, settings: PlayerSettings = PlayerSettings(), mode: Mode = .independent, initialFrame: Int64? = nil, serverPeriod: Int? = nil) {
        self.serverPeriod = serverPeriod
        self.file = file
        self.settings = settings
        self.mode = mode
        self.initialFrame = initialFrame
    }

    /// The ring buffer the program is given. It stops with an error when the buffer is not larger than a period of the
    /// server, and a buffer of two periods leaves it no margin: it is at least four periods.
    public var bufferFrames: Int { max(settings.bufferFrames, 4 * (serverPeriod ?? 0)) }

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
    case pause
    /// A frame of the file (not of the server).
    case seek(Int64)
    case quit

    /// The line sent to the standard input of the program.
    public var line: String {
        switch self {
        case .play: return "play"
        case .pause: return "pause"
        case .seek(let frame): return "seek \(max(frame, 0))"
        case .quit: return "quit"
        }
    }
}
