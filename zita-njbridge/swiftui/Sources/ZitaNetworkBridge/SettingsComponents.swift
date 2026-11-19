// SPDX-License-Identifier: GPL-3.0-or-later
//
// The rows, groups and pages of settings are those of Jack Play and Jack Capture, kept the same so that the pages of the tools of
// the collection look alike.

import AppearanceKit
import MatrixKit
import SwiftUI
import ZitaBridgeKit

/// A row of a settings group: title, an explanation under it, and the control on the right.
struct OptionRow<Control: View>: View {
    let title: LocalizedStringKey
    var systemImage: String?
    var subtitle: LocalizedStringKey?
    @ViewBuilder var control: Control

    init(_ title: LocalizedStringKey, _ subtitle: LocalizedStringKey? = nil, systemImage: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                if let systemImage { Label(title, systemImage: systemImage) } else { Text(title) }
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) { control }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}

struct SettingsGroup<Content: View>: View {
    let title: LocalizedStringKey?
    var systemImage: String?
    /// For the groups of one direction: its title (a rule, the picto, the name) stands for a title of the group.
    var direction: LinkDirection?
    var detail: LocalizedStringKey?
    @ViewBuilder var content: Content

    init(_ title: LocalizedStringKey, systemImage: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    /// The groups of one direction: they begin with the title of the direction.
    init(direction: LinkDirection, detail: LocalizedStringKey? = nil, @ViewBuilder content: () -> Content) {
        self.title = nil
        self.systemImage = nil
        self.direction = direction
        self.detail = detail
        self.content = content()
    }

    /// A group with no title of its own: the section it is in has one.
    init(@ViewBuilder content: () -> Content) {
        self.title = nil
        self.systemImage = nil
        self.content = content()
    }

    var body: some View {
        let rows = VStack(spacing: 0) {
            Group(subviews: content) { rows in
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 { Divider().padding(.leading, 14) }
                    row
                }
            }
        }
        .blockBackground()
        if let direction {
            DirectionContainer(direction: direction, detail: detail) { rows }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                if let title {
                    Group {
                        if let systemImage { Label(title, systemImage: systemImage) } else { Text(title) }
                    }
                    .font(.headline).foregroundStyle(.secondary).padding(.leading, 12)
                }
                rows
            }
        }
    }
}

/// A page of settings: scrolls, with the same margins everywhere.
struct SettingsPage<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) { content }
                .padding(24).frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
        }
        .softScrollEdges()
    }
}

/// A small note under a group.
struct GroupNote: View {
    let text: LocalizedStringKey
    var body: some View {
        Text(text).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12).fixedSize(horizontal: false, vertical: true)
    }
}

/// A number typed in a field: the text is kept apart so that the field can be emptied, and the number is taken when it is valid.
struct NumberField: View {
    let label: LocalizedStringKey
    @Binding var value: Int
    let range: ClosedRange<Int>
    var width: CGFloat = 76
    @State private var text = ""
    @FocusState private var focused: Bool

    private var isValid: Bool { Int(text).map(range.contains) ?? false }

    var body: some View {
        TextField(label, text: $text)
            .labelsHidden().textFieldStyle(.roundedBorder).frame(width: width)
            .focused($focused)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(isValid || text.isEmpty && focused ? .clear : Color.alert, lineWidth: 1).padding(-1))
            .onAppear { text = "\(value)" }
            .onChange(of: text) { _, new in
                let digits = new.filter(\.isNumber)
                if digits != new { text = digits; return }
                if let n = Int(digits), range.contains(n) { value = n }
            }
            .onChange(of: value) { _, new in if Int(text) != new { text = "\(new)" } }
            .onChange(of: focused) { _, now in if !now, !isValid { text = "\(value)" } }
    }
}

/// A point of the matrix, lit in the accent of the application. Drawn flat on every system: Liquid Glass tinted with the
/// accent would read as grey, and the lit point must show the accent.
struct AccentLED: View {
    let isOn: Bool
    let action: () -> Void
    @Environment(\.appAccentColor) private var accent
    @Environment(\.colorScheme) private var scheme
    @State private var isHovered = false

    private var fill: Color { isOn ? accent : (scheme == .dark ? .ledOffFill : Color(white: 0, opacity: 0.07)) }
    private var outline: Color {
        if isOn { return accent.opacity(isHovered ? 0.9 : 0.5) }
        let base = scheme == .dark ? Color.white : Color.black
        return base.opacity(isHovered ? 0.35 : (scheme == .dark ? 0.06 : 0.14))
    }

    var body: some View {
        Button(action: action) {
            Circle().fill(fill).overlay(Circle().strokeBorder(outline, lineWidth: 1)).frame(width: 16, height: 16)
                .shadow(color: isOn ? accent.opacity(isHovered ? 0.8 : 0.55) : .clear, radius: isHovered ? 5 : 4)
                .scaleEffect(isHovered ? 1.2 : 1)
                .frame(width: 40, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(.spring(duration: 0.2, bounce: 0.35)) { isHovered = hovering } }
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? Text("activé") : Text("désactivé"))
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

/// The title of a direction, the same everywhere: the picto in a tile, the name, and what it means. It marks where reception ends and
/// sending begins.
struct DirectionTitle: View {
    let direction: LinkDirection
    var detail: LocalizedStringKey?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: direction.symbol)
                .font(.system(size: 20, weight: .medium))
                .frame(width: 38, height: 38)
                .background(Color.primary.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 0) {
                Text(direction == .receive ? "Réception" : "Envoi").font(.title3).fontWeight(.semibold)
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
        }
    }
}

/// A direction of a page: an outlined container (a slightly raised fill and a hairline, as in the configuration of JackMate) that holds its
/// title and what belongs to it, so that reception and sending are two places and not one long list.
struct DirectionContainer<Content: View>: View {
    let direction: LinkDirection
    var detail: LocalizedStringKey?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DirectionTitle(direction: direction, detail: detail)
            content
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.14), lineWidth: 1))
    }
}
