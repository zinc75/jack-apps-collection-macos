// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation

/// The technical record of a recording that is done: what was asked for, what happened, what the file holds.
public struct RecordingSummary: Equatable, Sendable {
    /// The settings the recording was started with (a copy: the user may change them since).
    public var settings: CaptureSettings
    /// The command as it was run, for display.
    public var commandText: String
    public var sampleRate: Int
    public var startedAt: Date
    public var endedAt: Date
    public var file: URL
    public var bytes: Int64
    public var xruns: Int
    public var overruns: Int
    public var warnings: [String]
    /// Read back from the file.
    public var fileInfo: SoundFileInfo?
    /// The highest sample of each channel (1.0 is full scale); nil until it has been measured, or when the file cannot be read.
    public var peaks: [Float]?
    public var isMeasuringPeaks = false
    /// With file rotation the recording is several files ("<name>.00.<ext>", ".01", …): how many, and the
    /// duration of all of them. `file`, `fileInfo` and `peaks` stand for the first one, `bytes` for all.
    public var partCount = 1
    public var totalDuration: TimeInterval?

    /// The duration of the audio when the file could be read, else the time the recording took.
    public var duration: TimeInterval { totalDuration ?? fileInfo?.duration ?? endedAt.timeIntervalSince(startedAt) }
}
