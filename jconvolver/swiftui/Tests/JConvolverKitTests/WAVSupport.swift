// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Writes small WAV files for the tests: 16 bit integers or 32 bit floats, interleaved.
enum WAVSupport {
    enum Encoding { case int16, float32 }

    static func write(_ url: URL, channels: Int, rate: Int = 48000, encoding: Encoding = .float32, samples: [Float]) throws {
        var d = Data()
        func u32(_ v: Int) { var x = UInt32(v).littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: Int) { var x = UInt16(v).littleEndian; d.append(Data(bytes: &x, count: 2)) }
        let width = encoding == .int16 ? 2 : 4
        let bytes = samples.count * width
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + bytes); d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(encoding == .int16 ? 1 : 3); u16(channels); u32(rate)
        u32(rate * channels * width); u16(channels * width); u16(width * 8)
        d.append(contentsOf: Array("data".utf8)); u32(bytes)
        for s in samples {
            switch encoding {
            case .int16: var v = Int16(max(-1, min(1, s)) * 32767).littleEndian; d.append(Data(bytes: &v, count: 2))
            case .float32: var bits = s.bitPattern.littleEndian; d.append(Data(bytes: &bits, count: 4))
            }
        }
        try d.write(to: url)
    }
}
