// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation

public enum StartMode: String, CaseIterable, Sendable, Codable {
    case immediately
    /// `-jt`: start when the JACK transport rolls.
    case transport
    /// `-jf`: start when the server goes into freewheeling.
    case freewheel
}

/// A duration kept in seconds, typed as minutes and seconds.
public enum TimeSpan {
    /// A day at most, a second at least.
    public static let range = 1...86_400

    public static func seconds(minutes: Int, seconds: Int) -> Int {
        min(max(minutes * 60 + seconds, range.lowerBound), range.upperBound)
    }

    /// "4 min 25 s", "6 s", "10 min".
    public static func text(_ total: Int) -> String {
        let m = total / 60, s = total % 60
        return [m > 0 ? "\(m) min" : nil, s > 0 || m == 0 ? "\(s) s" : nil].compactMap { $0 }.joined(separator: " ")
    }
}

/// Everything the configuration view edits. The command line is a function of it.
public struct CaptureSettings: Equatable, Sendable, Codable {
    /// The base name of a recording file, in the language of the application ("Take" in English). Tests run without the catalogue and get the French key.
    public static var defaultName: String { String(localized: "Prise", bundle: .main, comment: "Default base name of a recording file") }
    /// The name of the recorder in the JACK graph. JACK accepts spaces in client names ("Jack Capture:input1").
    public static let defaultClientName = "Jack Capture"
    /// The name jack_capture gives itself when it is not told one.
    public static let programClientName = "jack_capture"

    public var channels = 2
    public var clientName = CaptureSettings.defaultClientName
    public var autoConnect = true
    /// Per channel, the JACK ports ("client:port") whose signals are summed into it.
    public var sources: [[String]] = []

    /// Folder of the recordings; a leading "~" is the home folder.
    public var folder = "~/Music/Jack Capture"
    public var name = CaptureSettings.defaultName
    public var numbering = true

    public private(set) var format = CaptureFormat.wav
    public var depth = SampleDepth.int24
    /// MP3 bit rate in kilobits per second.
    public var mp3Bitrate = 192
    /// Ogg Vorbis quality, from 0 to 100 (jack_capture takes 0.0 to 1.0).
    public var oggQuality = 50

    public var startMode = StartMode.immediately
    public var scheduledStop = false
    /// `-d`, in seconds.
    public var durationSeconds = 600
    public var timemachine = false
    public var timemachineSeconds = 3

    public var metersEnabled = true
    /// Listens to the chosen sources while nothing is recorded, to show their levels (a JACK client of its own).
    public var monitorsLevels = false
    /// `-S`: also write a text file with the time of the first frame, as `jack_capture` does.
    public var writesTimeFile = false
    public var rotatesFiles = false
    /// `-Rf`, in seconds of audio.
    public var rotationSeconds = 600
    public var bufferSeconds = 4
    public var oscEnabled = false
    public var oscPort = 7777
    /// The applications behind the clients seen so far (client name to bundle identifier), so that a client that is
    /// gone is still shown with the icon of its application. Learnt from the graph, never typed.
    public var knownBundles: [String: String] = [:]

    public init() {}

    /// What a format change did to the other settings.
    public struct FormatChange: Equatable, Sendable {
        public var channelsReduced = false
    }

    /// Changes the format and brings the dependent values back inside what it allows.
    @discardableResult
    public mutating func setFormat(_ newFormat: CaptureFormat) -> FormatChange {
        format = newFormat
        var change = FormatChange()
        if channels > newFormat.maxChannels {
            setChannels(newFormat.maxChannels)
            change.channelsReduced = true
        }
        if !newFormat.isLossy, !newFormat.depths.contains(depth) {
            depth = .int24
        }
        return change
    }

    /// Sets the number of channels inside the limit of the format and resizes the source lists.
    public mutating func setChannels(_ count: Int) {
        let n = min(max(count, 1), format.maxChannels)
        channels = n
        if sources.count > n { sources.removeLast(sources.count - n) }
    }

    /// The name without what would be taken for a path or an option by jack_capture.
    public var baseName: String {
        var s = name.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/", with: "-")
        while s.hasPrefix("-") { s.removeFirst() }
        return s.isEmpty ? CaptureSettings.defaultName : s
    }

    /// The JACK client name, without the ":" that separates client and port; empty means the default.
    public var jackClientName: String {
        let s = clientName.replacingOccurrences(of: ":", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? CaptureSettings.defaultClientName : s
    }

    public var folderURL: URL {
        URL(fileURLWithPath: (folder as NSString).expandingTildeInPath, isDirectory: true)
    }
}
