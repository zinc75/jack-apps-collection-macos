// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SoundFileKit

/// What the processing of a sound file produced, looked at once it is written: what the file is, how loud it gets, how big it is.
public struct OutputSummary: Equatable, Sendable {
    public var info: SoundFileInfo
    /// The highest absolute sample, from 0 up (1 is full scale).
    public var peak: Float
    public var bytes: Int64

    public var peakDecibels: Double { peak > 0 ? 20 * log10(Double(peak)) : -.infinity }

    /// Reads the whole file once, for the peak.
    public static func measure(url: URL) throws -> OutputSummary {
        let file = try SoundFile(url: url)
        let channels = file.channels
        var peak: Float = 0
        let block = 1 << 14
        var buffer = [Float](repeating: 0, count: block * channels)
        while true {
            let got = try buffer.withUnsafeMutableBufferPointer { try file.read(into: $0.baseAddress!, maxFrames: block) }
            if got == 0 { break }
            for i in 0..<(got * channels) { peak = max(peak, abs(buffer[i])) }
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
        return OutputSummary(info: file.info, peak: peak, bytes: size)
    }
}
