// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation

/// Whether a recording can be written in the chosen folder: looked at before the start, so that the
/// reason is told in words (jack_capture itself only says that it could not open the file).
public enum FolderCheck {
    public enum Problem: Equatable, Sendable {
        /// The folder is on a volume that is not mounted (an external disk that was unplugged).
        case volumeNotMounted(String)
        case notADirectory
        case notWritable
        /// Free bytes: too few to record anything worthwhile.
        case noSpace(Int64)
    }

    /// Less than this free and the recording is refused.
    public static let minimumFreeBytes: Int64 = 100_000_000

    public static func problem(for folder: URL, minimumFree: Int64 = minimumFreeBytes, fileManager fm: FileManager = .default) -> Problem? {
        let path = folder.standardizedFileURL.path
        let parts = path.split(separator: "/").map(String.init)
        if parts.count >= 2, parts[0] == "Volumes", !fm.fileExists(atPath: "/Volumes/\(parts[1])") {
            return .volumeNotMounted(parts[1])
        }
        // The folder may not exist yet: it is created below the nearest folder that does.
        var existing = URL(fileURLWithPath: path)
        var isDirectory: ObjCBool = false
        while !fm.fileExists(atPath: existing.path, isDirectory: &isDirectory), existing.pathComponents.count > 1 {
            existing.deleteLastPathComponent()
        }
        if !isDirectory.boolValue { return .notADirectory }
        if !fm.isWritableFile(atPath: existing.path) { return .notWritable }
        if let free = RecordingEstimate.availableBytes(at: existing, fileManager: fm), free < minimumFree { return .noSpace(free) }
        return nil
    }

    public static func message(_ problem: Problem, folder: URL) -> String {
        let shown = (folder.path as NSString).abbreviatingWithTildeInPath
        switch problem {
        case .volumeNotMounted(let name): return String(localized: "Le volume « \(name) » n'est pas monté. Branchez-le, ou choisissez un autre dossier.")
        case .notADirectory: return String(localized: "\(shown) n'est pas un dossier. Choisissez un autre dossier.")
        case .notWritable: return String(localized: "Le dossier \(shown) n'est pas accessible en écriture. Choisissez un autre dossier.")
        case .noSpace(let free):
            let size = ByteCountFormatter.string(fromByteCount: free, countStyle: .file)
            return String(localized: "Il ne reste que \(size) sur ce disque : trop peu pour enregistrer. Libérez de la place, ou choisissez un autre dossier.")
        }
    }
}
