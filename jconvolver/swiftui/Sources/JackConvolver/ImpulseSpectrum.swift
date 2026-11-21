// SPDX-License-Identifier: GPL-3.0-or-later

import AppearanceKit
import JConvolverKit
import SwiftUI

/// The spectrum of the part of an impulse response the engine reads: level in dB against frequency on a logarithmic axis, smoothed over
/// a fraction of an octave.
struct ImpulseSpectrumView: View {
    @Environment(\.appAccentColor) private var accent
    let data: CurveData
    let used: Range<Int>
    @State private var spectrum: Spectrum?
    @State private var fraction = 6.0

    private let leftMargin: CGFloat = 44, bottomMargin: CGFloat = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Canvas { context, size in draw(&context, size) }
                .frame(height: 190)
                .blockBackground()
                .accessibilityLabel("Spectre de la réponse impulsionnelle")
            HStack(spacing: 8) {
                Text("Lissage").foregroundStyle(.secondary)
                Picker("Lissage", selection: $fraction) {
                    Text("Aucun").tag(48.0)
                    Text("1/12 d'octave").tag(12.0)
                    Text("1/6 d'octave").tag(6.0)
                    Text("1/3 d'octave").tag(3.0)
                }
                .labelsHidden().fixedSize().controlSize(.small)
                Spacer()
            }
            .font(.caption)
        }
        .task(id: Key(range: used, fraction: fraction)) {
            let data = data, used = used, fraction = fraction
            spectrum = await Task.detached(priority: .userInitiated) {
                Spectrum(samples: data.samples, range: used, sampleRate: data.sampleRate, fractionOfOctave: fraction)
            }.value
        }
    }

    private struct Key: Hashable { var range: Range<Int>; var fraction: Double }

    private func draw(_ context: inout GraphicsContext, _ size: CGSize) {
        let plot = CGRect(x: leftMargin, y: 6, width: max(size.width - leftMargin - 8, 1), height: max(size.height - bottomMargin - 12, 1))
        let grid = Color.secondary.opacity(0.35)
        guard let spectrum, spectrum.points.count > 1 else { return }
        let lowest = spectrum.points.first!.frequency, highest = spectrum.points.last!.frequency
        let top = (spectrum.peakDecibels / 10).rounded(.up) * 10, bottom = top - 80
        func x(_ f: Double) -> CGFloat { plot.minX + CGFloat(log(f / lowest) / log(highest / lowest)) * plot.width }
        func y(_ db: Double) -> CGFloat { plot.minY + CGFloat((top - min(max(db, bottom), top)) / (top - bottom)) * plot.height }

        for db in stride(from: top, through: bottom, by: -20) {
            var line = Path(); line.move(to: CGPoint(x: plot.minX, y: y(db))); line.addLine(to: CGPoint(x: plot.maxX, y: y(db)))
            context.stroke(line, with: .color(grid), style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
            context.draw(Text(verbatim: "\(Int(db))").font(.caption2).foregroundColor(.secondary), at: CGPoint(x: plot.minX - 4, y: y(db)), anchor: .trailing)
        }
        for f in [20.0, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000] where f >= lowest && f <= highest {
            var line = Path(); line.move(to: CGPoint(x: x(f), y: plot.minY)); line.addLine(to: CGPoint(x: x(f), y: plot.maxY))
            context.stroke(line, with: .color(grid.opacity(0.6)), style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
            let label = f >= 1000 ? "\(Int(f / 1000)) k" : "\(Int(f))"
            context.draw(Text(verbatim: label).font(.caption2).foregroundColor(.secondary), at: CGPoint(x: x(f), y: plot.maxY + 11), anchor: .center)
        }
        var curve = Path()
        for (i, p) in spectrum.points.enumerated() {
            let point = CGPoint(x: x(p.frequency), y: y(p.decibels))
            i == 0 ? curve.move(to: point) : curve.addLine(to: point)
        }
        context.stroke(curve, with: .color(accent), style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
        context.draw(Text("dB").font(.caption2).foregroundColor(.secondary), at: CGPoint(x: 3, y: plot.minY), anchor: .topLeading)
    }
}
