// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation

/// Size of the file to expect and room left on the disk.
public enum RecordingEstimate {
    /// Bytes written per second; compressed formats are estimates.
    public static func bytesPerSecond(_ s: CaptureSettings, sampleRate: Int = 48_000) -> Double {
        let ch = Double(s.channels)
        switch s.format {
        case .mp3: return Double(s.mp3Bitrate) * 1000 / 8
        case .ogg: return ch * (3000 + Double(s.oggQuality) * 220)
        case .opus: return ch * 16_000
        case .flac: return ch * Double(sampleRate) * Double(s.depth.bytes) * 0.55
        case .wav, .rf64, .aiff, .caf, .w64: return ch * Double(sampleRate) * Double(s.depth.bytes)
        }
    }

    /// Free space for important usage on the volume holding `url`, looking at the nearest folder
    /// that exists (the recording folder may not have been created yet).
    public static func availableBytes(at url: URL, fileManager: FileManager = .default) -> Int64? {
        var dir = url
        while !fileManager.fileExists(atPath: dir.path), dir.pathComponents.count > 1 {
            dir.deleteLastPathComponent()
        }
        let values = try? dir.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }
}

/// File names of the recordings.
public enum FileNaming {
    /// The name jack_capture will pick: with numbering, the first free `<name>_NN.<ext>`
    /// (it tries 01, 02… and stops at the first name that does not exist); without, `<name>.<ext>`.
    public static func nextName(_ s: CaptureSettings, exists: (String) -> Bool) -> String {
        let ext = s.format.fileExtension
        guard s.numbering else { return "\(s.baseName).\(ext)" }
        for n in 1..<100_000 {
            let candidate = String(format: "%@_%02d.%@", s.baseName, n, ext)
            if !exists(candidate) { return candidate }
        }
        return "\(s.baseName)_100000.\(ext)"
    }

    public static func nextName(_ s: CaptureSettings, fileManager: FileManager = .default) -> String {
        let folder = s.folderURL
        return nextName(s) { fileManager.fileExists(atPath: folder.appendingPathComponent($0).path) }
    }
}
