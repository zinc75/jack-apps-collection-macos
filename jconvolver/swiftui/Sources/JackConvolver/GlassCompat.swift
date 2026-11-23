// SPDX-License-Identifier: GPL-3.0-or-later
//
// The glass and the cards are those of Jack Capture (GPL-2.0-or-later) and Jack Play, with the accent of this application.

import MatrixKit
import AppearanceKit
import AppKit
import SwiftUI

/// Liquid Glass on macOS 26, a close material look on macOS 15. The only place where the two differ, so that no view has
/// to test the system version.
extension View {
    /// A disc of the accent, for the round button. Drawn on every system: tinted Liquid Glass reads as grey with this
    /// colour, and the disc must show the accent.
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

extension View {
    /// A tab that is a cell of glass of its own: neutral Liquid Glass on macOS 26, the accent shining through when it is the one that is open (a
    /// glass tint reads grey with this colour, so the accent is under the glass); a bordered cell on a material before.
    @ViewBuilder
    func glassTab(selected: Bool, tint: Color) -> some View {
        if #available(macOS 26, *), GlassSupport.enabled {
            self.background {
                if selected { Capsule().fill(LinearGradient(colors: [tint.opacity(0.6), tint.opacity(0.85)], startPoint: .top, endPoint: .bottom)) }
            }
            .glassEffect(.regular.interactive(), in: Capsule())
        } else {
            self.background(selected ? tint.opacity(0.9) : Color.primary.opacity(0.07), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(selected ? 0 : 0.14), lineWidth: 0.75))
        }
    }

    /// Lets the glass cells of its content be seen as one family: they share the lighting and may merge when they touch.
    @ViewBuilder
    func glassGroup(spacing: CGFloat) -> some View {
        if #available(macOS 26, *), GlassSupport.enabled { GlassEffectContainer(spacing: spacing) { self } } else { self }
    }
}

/// Tabs of equal width over the whole width of their container, a cell of glass each (see `glassTab`): the one that is open has the accent. The
/// segmented control of the system keeps its natural width and leaves the other tabs without a shape.
struct GlassTabs<Tag: Hashable>: View {
    @Binding var selection: Tag
    let items: [(tag: Tag, title: String)]
    @Environment(\.appAccentColor) private var accent

    var body: some View {
        HStack(spacing: 8) {
            ForEach(items, id: \.tag) { item in
                let selected = selection == item.tag
                Button { selection = item.tag } label: {
                    Text(verbatim: item.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.8))
                        .glassTab(selected: selected, tint: accent)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .glassGroup(spacing: 8)
    }
}

extension View {
    /// A card of Liquid Glass on macOS 26 (it answers the pointer when it is a button), a light panel with a border before. Under the pointer
    /// (`hovered`) the edge takes a little of the accent.
    /// A card that is the one chosen (`selected`) keeps a little of the accent: the edge and a faint shadow.
    func glassCard(cornerRadius: CGFloat = 14, interactive: Bool = true, hovered: Bool = false, selected: Bool = false) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius, interactive: interactive, hovered: hovered, selected: selected))
    }
}

private struct GlassCard: ViewModifier {
    let cornerRadius: CGFloat
    let interactive: Bool
    let hovered: Bool
    let selected: Bool
    @Environment(\.appAccentColor) private var accent

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        Group {
            if #available(macOS 26, *), GlassSupport.enabled {
                content.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
            } else {
                content.background(Color.primary.opacity(hovered ? 0.06 : 0.035), in: shape)
                    .overlay(shape.strokeBorder(Color.primary.opacity(0.14), lineWidth: 1))
            }
        }
        // The effect of the pointer, the same on glass and on the panel that stands in for it: discreet, an edge in the accent and a faint shadow.
        .overlay(shape.strokeBorder(accent.opacity(selected ? 0.55 : (hovered ? 0.35 : 0)), lineWidth: 1))
        .shadow(color: accent.opacity(selected ? 0.16 : (hovered ? 0.12 : 0)), radius: selected || hovered ? 9 : 0, y: selected || hovered ? 3 : 0)
        .animation(.easeOut(duration: 0.18), value: hovered)
        .animation(.easeOut(duration: 0.2), value: selected)
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
    enum Kind { case plain, warn, accent, ok, bad }
    let text: Text
    var kind: Kind = .plain
    var symbol: String?
    @Environment(\.appAccentColor) private var accent

    var body: some View {
        let color: Color = switch kind { case .plain: .secondary; case .warn: .orange; case .accent: accent; case .ok: .green; case .bad: .red }
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
