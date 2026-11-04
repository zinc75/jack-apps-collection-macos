// SPDX-License-Identifier: GPL-2.0-or-later

import XCTest
import AVFoundation
@testable import JackCaptureKit

final class SoundFileInfoTests: XCTestCase {
    /// A sine of the given amplitude, one second, written by the system in the given container.
    private func writeSine(ext: String, settings: [String: Any], channels: AVAudioChannelCount = 2, amplitude: Float = 0.5) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sfi-\(UUID().uuidString).\(ext)")
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: channels, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000)!
        buffer.frameLength = 48_000
        for c in 0..<Int(channels) {
            for i in 0..<48_000 { buffer.floatChannelData![c][i] = (c == 0 ? amplitude : amplitude / 2) * sinf(Float(i) * 0.05) }
        }
        var merged = settings
        merged[AVSampleRateKey] = 48_000
        merged[AVNumberOfChannelsKey] = Int(channels)
        let file = try AVAudioFile(forWriting: url, settings: merged, commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buffer)
        return url
    }

    private func pcm(bits: Int, float: Bool = false, bigEndian: Bool = false) -> [String: Any] {
        [AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: bits, AVLinearPCMIsFloatKey: float,
         AVLinearPCMIsBigEndianKey: bigEndian, AVLinearPCMIsNonInterleaved: false]
    }

    func testAWav24() throws {
        let url = try writeSine(ext: "wav", settings: pcm(bits: 24))
        let info = try XCTUnwrap(SoundFileInfo.read(url))
        XCTAssertEqual(info.container, "WAV (Microsoft)")
        XCTAssertEqual(info.encoding, .pcmSigned(bits: 24))
        XCTAssertEqual(info.encoding?.sndfileName, "Signed 24 bit PCM")
        XCTAssertEqual(info.endianness, "Little endian")
        XCTAssertEqual(info.sampleRate, 48_000)
        XCTAssertEqual(info.channels, 2)
        XCTAssertEqual(info.frames, 48_000)
        XCTAssertEqual(try XCTUnwrap(info.duration), 1, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(info.bitRate), 48_000 * 2 * 24 / 1000, accuracy: 60)   // the header of a file of one second weighs
    }

    func testFloat32AndAnAiffAreBigEndian() throws {
        let wav = try XCTUnwrap(SoundFileInfo.read(try writeSine(ext: "wav", settings: pcm(bits: 32, float: true))))
        XCTAssertEqual(wav.encoding, .float(bits: 32))
        let aiff = try XCTUnwrap(SoundFileInfo.read(try writeSine(ext: "aiff", settings: pcm(bits: 16, bigEndian: true))))
        XCTAssertEqual(aiff.container, "AIFF (Apple/SGI)")
        XCTAssertEqual(aiff.endianness, "Big endian")
        XCTAssertEqual(aiff.encoding, .pcmSigned(bits: 16))
    }

    func testThePeaksPerChannel() throws {
        let url = try writeSine(ext: "wav", settings: pcm(bits: 24), amplitude: 0.5)
        let peaks = try XCTUnwrap(SoundFileInfo.peaks(of: url))
        XCTAssertEqual(peaks.count, 2)
        XCTAssertEqual(peaks[0], 0.5, accuracy: 0.001)
        XCTAssertEqual(peaks[1], 0.25, accuracy: 0.001)
    }

    func testTheContainerIsToldByTheMagicNumbers() {
        func container(_ s: String) -> String { SoundFileInfo.sniff(Data(s.utf8) + Data(repeating: 0, count: 40)).container }
        XCTAssertEqual(container("RF64\0\0\0\0WAVE"), "RF64 (EBU)")
        XCTAssertEqual(container("fLaC"), "FLAC (FLAC Lossless Audio Codec)")
        XCTAssertEqual(container("caff"), "CAF (Apple Core Audio File)")
        XCTAssertEqual(container("OggS"), "OGG (OGG Container format)")
        XCTAssertEqual(container("????"), "Unknown")
        XCTAssertEqual(SoundFileInfo.sniff(Data("OggS".utf8) + Data("\u{01}vorbis".utf8)).encoding, .vorbis)
        XCTAssertEqual(SoundFileInfo.sniff(Data("OggS".utf8) + Data("OpusHead".utf8)).encoding, .opus)
    }

    func testAnUnreadableFileHasNoInfo() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sfi-\(UUID().uuidString).wav")
        try Data("no".utf8).write(to: url)
        XCTAssertNil(SoundFileInfo.read(url))
        XCTAssertNil(SoundFileInfo.peaks(of: url))
    }
}
