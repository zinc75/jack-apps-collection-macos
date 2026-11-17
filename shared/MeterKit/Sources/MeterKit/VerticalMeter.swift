// SPDX-License-Identifier: MIT

import SwiftUI

/// A thin vertical meter for one channel, to sit beside the lane of that channel: the level rises from the bottom, the peak it
/// holds is a mark, and a red mark at the top says it clipped.
public struct VerticalMeter: View {
    let meter: ChannelMeter

    public init(meter: ChannelMeter) { self.meter = meter }

    public var body: some View {
        let meter = self.meter   // read here, so that the view is rebuilt when it changes
        Canvas { context, size in
            let track = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: min(size.width / 2, 3))
            context.fill(track, with: .color(.primary.opacity(0.09)))
            let gradient = Gradient(stops: [
                .init(color: Color(red: 0.13, green: 0.77, blue: 0.37), location: 0),
                .init(color: Color(red: 0.13, green: 0.77, blue: 0.37), location: 0.55),
                .init(color: Color(red: 0.98, green: 0.80, blue: 0.08), location: 0.78),
                .init(color: Color(red: 0.98, green: 0.45, blue: 0.09), location: 0.9),
                .init(color: Color(red: 0.94, green: 0.27, blue: 0.27), location: 1),
            ])
            if meter.level > 0 {
                let h = size.height * min(meter.level, 1)
                var layer = context
                layer.clip(to: track)
                layer.fill(Path(CGRect(x: 0, y: size.height - h, width: size.width, height: h)),
                           with: .linearGradient(gradient, startPoint: CGPoint(x: 0, y: size.height), endPoint: CGPoint(x: 0, y: 0)))
            }
            if meter.peak > 0 {
                let y = size.height * (1 - min(meter.peak, 1))
                context.fill(Path(CGRect(x: -1, y: y - 1, width: size.width + 2, height: 2)), with: .color(.primary.opacity(0.85)))
            }
            if meter.clipped {
                context.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: size.width, height: 3), cornerRadius: 1.5),
                             with: .color(Color(red: 0.94, green: 0.27, blue: 0.27)))
            }
        }
        .accessibilityHidden(true)
    }
}
