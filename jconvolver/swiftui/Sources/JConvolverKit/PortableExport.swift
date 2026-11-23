// SPDX-License-Identifier: GPL-3.0-or-later

import CSndfile
import Foundation
import SoundFileKit

/// What the person chooses for a portable version of a configuration: one audio file with every impulse response that the configuration reads, and a
/// new configuration file that refers to it, to be sent as they are. The files of the original and the configuration that is open are not changed.
public struct PortableOptions: Equatable, Sendable {
    public enum Container: String, Sendable, CaseIterable { case wav, caf }
    public enum Precision: Sendable { case source, float32 }
    /// What is left in the folder: the two files, the two files and an archive that holds them, or the archive alone.
    public enum Output: Sendable, CaseIterable { case files, filesAndArchive, archiveOnly }

    /// The name of the files, without extension: `<name>.wav` (or `.caf`), `<name>.conf` and `<name>.zip`.
    public var name: String
    public var container: Container
    public var precision: Precision
    /// Gain, delay, start and length are applied to the samples: the configuration then keeps only the numbers of the channels.
    public var appliesSettings: Bool
    public var output: Output

    public init(name: String, container: Container = .wav, precision: Precision = .source, appliesSettings: Bool = false, output: Output = .files) {
        self.name = name
        self.container = container
        self.precision = precision
        self.appliesSettings = appliesSettings
        self.output = output
    }

    /// A name that is one name of a file: no folder separator, no colon, no blank at the ends.
    public static func cleaned(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// What prevents a portable version from being made.
public enum PortableBlocker: Equatable, Sendable {
    /// No impulse response is read from a file: there is nothing to put together.
    case noFileImpulse
    case fileMissing(path: String)
    case channelMissing(path: String, channel: Int, channels: Int)
    /// The files have not all the same sample rate, and one audio file has only one.
    case differentRates([Double])
    case emptyName
}

/// The plan of a portable version: the channels of the audio file, how long it is, how big, and what blocks it.
public struct PortablePlan: Equatable, Sendable {
    /// One channel of the audio file: a part of a channel of a file of the original, with what is applied to it when the settings are written in.
    struct Track: Equatable, Sendable {
        var path: String
        /// The channel of the file, from 1.
        var channel: Int
        /// The first frame read, the number read, the gain and the silence put before.
        var start: Int
        var count: Int
        var gain: Float
        var delay: Int
        /// Frames the channel takes in the new file.
        var frames: Int { max(delay + count, 1) }
    }

    var tracks: [Track]
    /// For each place of the matrix that reads a file (its pair, and its place among the responses of the pair), the channel of the new file, from 1.
    var assignment: [Place: Int]
    struct Place: Hashable, Sendable { var pair: ConvPair; var index: Int }

    public var blockers: [PortableBlocker]
    /// The responses read from a file, the files they are in and the folders of those.
    public var impulses: Int
    public var files: Int
    public var folders: Int
    public var sampleRate: Double?
    /// The number of channels and of frames of the audio file.
    public var channels: Int { tracks.count }
    public var frames: Int
    /// Bytes of a sample in the audio file, and the libsndfile subtype that writes it.
    public var bytesPerSample: Int
    public var subtype: Int32
    /// The lines of the new configuration file.
    public var configLines: Int
    /// Whether the audio file is too big for a WAV file (4 GB).
    public var requiresCAF: Bool

    /// The size of the audio file, a little more than its samples.
    public var audioBytes: Int { channels * frames * bytesPerSample + 1024 }
    public var isBlocked: Bool { !blockers.isEmpty }

    /// Works out the portable version of a configuration.
    /// - Parameters:
    ///   - configDirectory: the folder of the configuration file, from which the names of files without a folder are read.
    ///   - automatic: the numbers of `/convolver/new` that the person did not set, as they are for the original.
    public static func make(document: ConvDocument, options: PortableOptions, configDirectory: String, automatic: ConvHeader,
                            fileInfo: (String) -> SoundFileInfo?) -> PortablePlan {
        var blockers: [PortableBlocker] = []
        var tracks: [Track] = []
        var assignment: [Place: Int] = [:]
        var byKey: [String: Int] = [:]
        var paths: [String] = []
        var rates: [Double] = []
        var impulses = 0
        var reported: Set<String> = []
        var infos: [SoundFileInfo] = []
        var gainAboveOne = false

        for pair in document.content.impulses.keys.sorted() {
            for (index, impulse) in (document.content.impulses[pair] ?? []).enumerated() {
                guard case .file(let file, let channel) = impulse.source else { continue }
                impulses += 1
                let path = ConvConfig.path(of: file, directory: impulse.directory, configDirectory: configDirectory)
                if !paths.contains(path) { paths.append(path) }
                guard let info = fileInfo(path) else {
                    if reported.insert(path).inserted { blockers.append(.fileMissing(path: path)) }
                    continue
                }
                guard channel >= 1, channel <= info.channels else {
                    if reported.insert("\(path)#\(channel)").inserted { blockers.append(.channelMissing(path: path, channel: channel, channels: info.channels)) }
                    continue
                }
                if !rates.contains(info.sampleRate) { rates.append(info.sampleRate) }
                if !infos.contains(info) { infos.append(info) }
                let total = Int(info.frames)
                if options.appliesSettings {
                    let start = min(max(impulse.offset, 0), total)
                    let end = impulse.length > 0 ? min(start + impulse.length, total) : total
                    tracks.append(Track(path: path, channel: channel, start: start, count: max(end - start, 0), gain: Float(impulse.gain), delay: max(impulse.delay, 0)))
                    if abs(impulse.gain) > 1 { gainAboveOne = true }
                    assignment[Place(pair: pair, index: index)] = tracks.count
                } else {
                    let key = "\(path)#\(channel)"
                    if let known = byKey[key] {
                        assignment[Place(pair: pair, index: index)] = known + 1
                    } else {
                        tracks.append(Track(path: path, channel: channel, start: 0, count: total, gain: 1, delay: 0))
                        byKey[key] = tracks.count - 1
                        assignment[Place(pair: pair, index: index)] = tracks.count
                    }
                }
            }
        }
        if impulses == 0 { blockers.append(.noFileImpulse) }
        if rates.count > 1 { blockers.append(.differentRates(rates.sorted())) }
        if options.name.isEmpty { blockers.append(.emptyName) }

        // The precision of the files, the highest of them; the sample rate of the original files when they all have the same.
        var subtype = Int32(SF_FORMAT_FLOAT)
        var bytes = 4
        if options.precision == .source, !infos.isEmpty, !(options.appliesSettings && gainAboveOne) {
            let integers = infos.compactMap { info -> Int? in
                if info.isLossy || info.encoding.lowercased().contains("float") || info.encoding.lowercased().contains("double") { return nil }
                return info.bitsPerSample
            }
            if integers.count == infos.count, let widest = integers.max() {
                switch widest {
                case ...16: subtype = Int32(SF_FORMAT_PCM_16); bytes = 2
                case 17...24: subtype = Int32(SF_FORMAT_PCM_24); bytes = 3
                default: subtype = Int32(SF_FORMAT_PCM_32); bytes = 4
                }
            }
        }
        let frames = max(tracks.map(\.frames).max() ?? 1, 1)
        var plan = PortablePlan(tracks: tracks, assignment: assignment, blockers: blockers, impulses: impulses, files: paths.count,
                                folders: Set(paths.map { ($0 as NSString).deletingLastPathComponent }).count, sampleRate: rates.first,
                                frames: frames, bytesPerSample: bytes, subtype: subtype, configLines: 0, requiresCAF: false)
        plan.requiresCAF = plan.audioBytes > 4_000_000_000
        let audioName = options.name + "." + (plan.requiresCAF ? PortableOptions.Container.caf.rawValue : options.container.rawValue)
        plan.configLines = plan.makeDocument(from: document, audioName: audioName, configDirectory: configDirectory, appliesSettings: options.appliesSettings,
                                             fileInfo: fileInfo).makeConfig(automatic: automatic).text.split(separator: "\n", omittingEmptySubsequences: false).count - 1
        return plan
    }

    /// The configuration of the portable version: the same, with every response from a file read from the new audio file.
    func makeDocument(from document: ConvDocument, audioName: String, configDirectory: String, appliesSettings: Bool,
                      fileInfo: (String) -> SoundFileInfo?) -> ConvDocument {
        var result = document
        for pair in document.content.impulses.keys.sorted() {
            var list = document.content.impulses[pair] ?? []
            for (index, impulse) in list.enumerated() {
                guard case .file(let file, _) = impulse.source, let channel = assignment[Place(pair: pair, index: index)] else { continue }
                var changed = impulse
                changed.source = .file(path: audioName, channel: channel)
                changed.directory = nil
                let track = tracks[channel - 1]
                if appliesSettings {
                    // What was set is in the samples now: the response is read whole, as long as it is.
                    changed.gain = 1; changed.delay = 0; changed.offset = 0
                    changed.length = track.frames
                } else if impulse.length == 0 {
                    // A channel of the new file is as long as the longest, and the end of a shorter one is silence: the response says where it ends.
                    let path = ConvConfig.path(of: file, directory: impulse.directory, configDirectory: configDirectory)
                    let total = fileInfo(path).map { Int($0.frames) } ?? 0
                    changed.length = total > impulse.offset ? total - impulse.offset : 0
                }
                list[index] = changed
            }
            result.content.impulses[pair] = list
        }
        return result
    }
}

public enum PortableError: Error, Equatable {
    case blocked
    case cannotRead(String)
    case tooLarge
    case cannotWrite(String)
    case archiveFailed(String)
}

/// What a portable version made.
public struct PortableResult: Equatable, Sendable {
    public var audio: URL?
    public var configuration: URL?
    public var archive: URL?
}

public enum PortableExporter {
    /// Largest set of source files read, in samples (in memory, as 32 bit floats).
    static let maximumSamples = 600_000_000

    /// The files that an export writes in `folder`, so that the person can be asked before they are replaced.
    public static func targets(plan: PortablePlan, options: PortableOptions, in folder: URL) -> [URL] {
        let ext = plan.requiresCAF ? "caf" : options.container.rawValue
        switch options.output {
        case .files: return [folder.appendingPathComponent("\(options.name).\(ext)"), folder.appendingPathComponent("\(options.name).conf")]
        case .filesAndArchive: return [folder.appendingPathComponent("\(options.name).\(ext)"), folder.appendingPathComponent("\(options.name).conf"),
                                       folder.appendingPathComponent("\(options.name).zip")]
        case .archiveOnly: return [folder.appendingPathComponent("\(options.name).zip")]
        }
    }

    /// Writes the portable version of `document` in `folder`.
    ///
    /// The audio file and the configuration are written first in a folder of their own (hidden, in `folder`), then moved to their place, so that a
    /// failure leaves what was there. The files of the original are only read.
    public static func export(document: ConvDocument, plan: PortablePlan, options: PortableOptions, configDirectory: String, automatic: ConvHeader,
                              fileInfo: (String) -> SoundFileInfo?, to folder: URL) throws -> PortableResult {
        guard !plan.isBlocked, let rate = plan.sampleRate else { throw PortableError.blocked }
        let container = plan.requiresCAF ? PortableOptions.Container.caf : options.container
        let audioName = "\(options.name).\(container.rawValue)", configName = "\(options.name).conf", archiveName = "\(options.name).zip"

        let fileManager = FileManager.default
        let staging = folder.appendingPathComponent(".portable-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        try writeAudio(plan: plan, container: container, rate: rate, to: staging.appendingPathComponent(audioName))
        let config = plan.makeDocument(from: document, audioName: audioName, configDirectory: configDirectory, appliesSettings: options.appliesSettings,
                                       fileInfo: fileInfo).makeConfig(automatic: automatic)
        do { try config.text.write(to: staging.appendingPathComponent(configName), atomically: true, encoding: .utf8) } catch {
            throw PortableError.cannotWrite(error.localizedDescription)
        }

        var result = PortableResult()
        if options.output != .files {
            let partial = staging.deletingLastPathComponent().appendingPathComponent(".portable-\(UUID().uuidString).zip")
            try archive(staging, to: partial)
            result.archive = try place(partial, as: folder.appendingPathComponent(archiveName))
        }
        if options.output != .archiveOnly {
            result.audio = try place(staging.appendingPathComponent(audioName), as: folder.appendingPathComponent(audioName))
            result.configuration = try place(staging.appendingPathComponent(configName), as: folder.appendingPathComponent(configName))
        }
        return result
    }

    /// Moves a file to its place, replacing what is there.
    private static func place(_ file: URL, as destination: URL) throws -> URL {
        let fileManager = FileManager.default
        do {
            if fileManager.fileExists(atPath: destination.path) { _ = try fileManager.replaceItemAt(destination, withItemAt: file) }
            else { try fileManager.moveItem(at: file, to: destination) }
        } catch {
            throw PortableError.cannotWrite(error.localizedDescription)
        }
        return destination
    }

    /// An archive that holds the files of `folder` at its root, as the Finder makes one.
    private static func archive(_ folder: URL, to destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--norsrc", folder.path, destination.path]
        let errors = Pipe()
        process.standardError = errors
        do { try process.run() } catch { throw PortableError.archiveFailed(error.localizedDescription) }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let text = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw PortableError.archiveFailed(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// A whole file as floats, interleaved.
    private final class Source {
        let samples: [Float]
        let channels: Int
        init(samples: [Float], channels: Int) { self.samples = samples; self.channels = channels }
    }

    private static func read(_ path: String) throws -> Source {
        var info = SF_INFO()
        guard let handle = sf_open(path, Int32(SFM_READ), &info) else { throw PortableError.cannotRead(path) }
        defer { sf_close(handle) }
        let channels = Int(info.channels), frames = Int(info.frames)
        guard channels >= 1, frames >= 0 else { throw PortableError.cannotRead(path) }
        var samples = [Float](repeating: 0, count: frames * channels)
        let got = samples.withUnsafeMutableBufferPointer { Int(sf_readf_float(handle, $0.baseAddress, sf_count_t(frames))) }
        guard got == frames else { throw PortableError.cannotRead(path) }
        return Source(samples: samples, channels: channels)
    }

    private static func writeAudio(plan: PortablePlan, container: PortableOptions.Container, rate: Double, to url: URL) throws {
        var sources: [String: Source] = [:]
        var total = 0
        for track in plan.tracks where sources[track.path] == nil {
            let source = try read(track.path)
            total += source.samples.count
            guard total <= maximumSamples else { throw PortableError.tooLarge }
            sources[track.path] = source
        }
        var info = SF_INFO()
        info.channels = Int32(plan.channels)
        info.samplerate = Int32(rate.rounded())
        info.format = (container == .wav ? Int32(SF_FORMAT_WAV) : Int32(SF_FORMAT_CAF)) | plan.subtype
        guard sf_format_check(&info) != 0 else { throw PortableError.cannotWrite("format") }
        guard let handle = sf_open(url.path, Int32(SFM_WRITE), &info) else { throw PortableError.cannotWrite(String(cString: sf_strerror(nil))) }
        _ = sf_command(handle, Int32(SFC_SET_CLIPPING), nil, Int32(SF_TRUE))

        let channels = plan.channels, block = 1 << 15
        var buffer = [Float](repeating: 0, count: block * channels)
        var frame = 0
        var failed = false
        while frame < plan.frames, !failed {
            let count = min(block, plan.frames - frame)
            for (c, track) in plan.tracks.enumerated() {
                let source = sources[track.path]!
                let stride = source.channels, column = track.channel - 1
                for i in 0..<count {
                    // The sample of the response that is at this frame of the new file: after the delay, as long as the part that is read.
                    let inside = frame + i - track.delay
                    buffer[i * channels + c] = inside >= 0 && inside < track.count ? source.samples[(track.start + inside) * stride + column] * track.gain : 0
                }
            }
            let written = buffer.withUnsafeBufferPointer { Int(sf_writef_float(handle, $0.baseAddress, sf_count_t(count))) }
            if written != count { failed = true }
            frame += count
        }
        let status = sf_error(handle)
        let message = String(cString: sf_strerror(handle))
        sf_close(handle)
        guard !failed, status == 0 else {
            try? FileManager.default.removeItem(at: url)
            throw PortableError.cannotWrite(message)
        }
    }
}
