// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import JConvolverKit
import PlotKit

/// What the plots of an impulse response need from its file, read off the main actor: the samples of a channel and the pyramid of their peaks.
enum ImpulseLoading {
    /// Every channel of a file, with its pyramid, in one pass over the file.
    static func loadAll(path: String) async -> [(CurveData, PeakPyramid)]? {
        await Task.detached(priority: .userInitiated) { () -> [(CurveData, PeakPyramid)]? in
            guard let curves = try? CurveData.loadAll(url: URL(fileURLWithPath: path)), !curves.isEmpty else { return nil }
            return curves.map { ($0, PeakPyramid(samples: $0.samples)) }
        }.value
    }

    static func load(path: String, channel: Int) async -> (CurveData, PeakPyramid)? {
        await Task.detached(priority: .userInitiated) { () -> (CurveData, PeakPyramid)? in
            guard let curve = try? CurveData.load(url: URL(fileURLWithPath: path), channel: channel) else { return nil }
            return (curve, PeakPyramid(samples: curve.samples))
        }.value
    }
}
