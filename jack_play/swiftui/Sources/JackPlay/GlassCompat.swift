// SPDX-License-Identifier: GPL-3.0-or-later
//
// The glass and the cards are those of Jack Capture (GPL-2.0-or-later), with the accent of this application.

import MatrixKit
import AppearanceKit
import SwiftUI

/// Liquid Glass on macOS 26, a close material look on macOS 15. The only place where the two differ, so that no view has
/// to test the system version.
extension View {
    /// A disc of the accent, for the play button. Drawn on every system: tinted Liquid Glass reads as grey with this
    /// teal, and the disc must show the accent.
    func accentGlassDisc(_ color: Color) -> some View {
        background {
            Circle()
                .fill(LinearGradient(colors: [color.opacity(0.78), color, color.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                .overlay(Circle().inset(by: 0.5).strokeBorder(.white.opacity(0.55), lineWidth: 0.5))
                .overlay(Circle().strokeBorder(.black.opacity(0.4), lineWidth: 0.5))
                .overlay(alignment: .top) { Ellipse().fill(.white.opacity(0.3)).frame(width: 36, height: 13).offset(y: 5).blur(radius: 2.5) }
                .shadow(color: color.opacity(0.4), radius: 8, y: 4)
        }
    }

    /// A neutral glass disc, for the small round buttons.
    @ViewBuilder
    func glassCircle(tint: Color? = nil) -> some View {
        if #available(macOS 26, *), GlassSupport.enabled {
            self.glassEffect(tint.map { .regular.tint($0) } ?? .regular, in: .circle)
        } else {
            self.background(tint?.opacity(0.35) ?? Color.primary.opacity(0.08), in: Circle())
                .overlay(Circle().strokeBorder(.primary.opacity(0.12), lineWidth: 0.5))
        }
    }
}

/// A rounded panel, as the grouped sections of System Settings but for free-form content.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .blockBackground()
    }
}

/// No chrome, a small dip under the click, and the whole label answers the click, not only its pixels (an icon alone
/// leaves most of a round button without a hit area). Dimmed when disabled.
struct PressStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .opacity(isEnabled ? 1 : 0.4)
            .animation(.spring(duration: 0.2, bounce: 0.4), value: configuration.isPressed)
    }
}

/// A small capsule of information: the format of the file, its rate. `warn` and `accent` colour it.
struct Chip: View {
    enum Kind { case plain, warn, accent }
    let text: Text
    var kind: Kind = .plain
    var symbol: String?
    @Environment(\.appAccentColor) private var accent

    var body: some View {
        let color: Color = switch kind { case .plain: .secondary; case .warn: .orange; case .accent: accent }
        HStack(spacing: 5) {
            if let symbol { Image(systemName: symbol).font(.system(size: 10, weight: .semibold)) }
            text
        }
        .font(.caption).fontWeight(.medium)
        .foregroundStyle(color)
        .padding(.horizontal, 9).frame(height: 22)
        .background(kind == .plain ? Color.primary.opacity(0.07) : color.opacity(0.14), in: Capsule())
    }
}

/// The number of a channel, in a disc.
struct ChannelNumber: View {
    let number: Int
    var warns = false
    var body: some View {
        Text(verbatim: "\(number)")
            .font(.system(size: 11, weight: .semibold).monospacedDigit())
            .frame(width: 20, height: 20)
            .background(warns ? Color.orange.opacity(0.3) : Color.primary.opacity(0.1), in: Circle())
    }
}
