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
    let title: LocalizedStringKey
    var systemImage: String?
    @ViewBuilder var content: Content

    init(_ title: LocalizedStringKey, systemImage: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if let systemImage { Label(title, systemImage: systemImage) } else { Text(title) }
            }
            .font(.headline).foregroundStyle(.secondary).padding(.leading, 12)
            VStack(spacing: 0) {
                Group(subviews: content) { rows in
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        if index > 0 { Divider().padding(.leading, 14) }
                        row
                    }
                }
            }
            .blockBackground()
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
    var width: CGFloat = 90
    @State private var text = ""
    @FocusState private var focused: Bool

    private var isValid: Bool { Int(text).map(range.contains) ?? false }

    var body: some View {
        TextField(label, text: $text)
            .labelsHidden().multilineTextAlignment(.trailing).frame(width: width)
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

/// A list of channels typed as the programs read it ("1-8", "9-16", "1,5"): the text is kept apart so that the field can be
/// emptied, and the list is taken when it is valid.
struct ChannelListField: View {
    @Binding var channels: [Int]
    var width: CGFloat = 120
    @State private var text = ""
    @FocusState private var focused: Bool

    private var parsed: [Int]? { ChannelList.parse(text) }

    var body: some View {
        TextField("Voies", text: $text)
            .labelsHidden().multilineTextAlignment(.trailing).frame(width: width).autocorrectionDisabled()
            .focused($focused)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(parsed != nil || text.isEmpty && focused ? .clear : Color.alert, lineWidth: 1).padding(-1))
            .onAppear { text = ChannelList.format(channels) }
            .onChange(of: text) { _, _ in if let list = parsed, list != channels { channels = list } }
            .onChange(of: channels) { _, new in if ChannelList.parse(text) != new { text = ChannelList.format(new) } }
            .onChange(of: focused) { _, now in if !now, parsed == nil { text = ChannelList.format(channels) } }
    }
}
