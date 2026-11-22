// SPDX-License-Identifier: GPL-3.0-or-later
//
// The rows, groups and pages of settings are those of Jack Play, Jack Capture and Zita Network Bridge, kept the same so that the
// pages of the tools of the collection look alike.

import AppearanceKit
import MatrixKit
import SwiftUI

/// A row of a settings group: title, an explanation under it, and the control on the right.
struct OptionRow<Control: View>: View {
    let title: LocalizedStringKey
    var systemImage: String?
    var subtitle: LocalizedStringKey?
    /// The detail, in a popover behind an "i" next to the title: the line under the title stays short.
    var info: LocalizedStringKey?
    @ViewBuilder var control: Control

    init(_ title: LocalizedStringKey, _ subtitle: LocalizedStringKey? = nil, info: LocalizedStringKey? = nil, systemImage: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.subtitle = subtitle
        self.info = info
        self.systemImage = systemImage
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if let systemImage { Label(title, systemImage: systemImage) } else { Text(title) }
                    if let info { InfoButton(text: info) }
                }
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

/// A small "i": the detail of a setting, in a popover.
struct InfoButton: View {
    let text: LocalizedStringKey
    @State private var shown = false

    var body: some View {
        Button { shown.toggle() } label: { Image(systemName: "info.circle").foregroundStyle(.secondary) }
            .buttonStyle(.plain)
            .help("Plus de détails")
            .popover(isPresented: $shown, arrowEdge: .bottom) {
                Text(text).font(.callout).fixedSize(horizontal: false, vertical: true).frame(width: 320, alignment: .leading).padding(14)
            }
    }
}

struct SettingsGroup<Content: View>: View {
    let title: LocalizedStringKey?
    var systemImage: String?
    @ViewBuilder var content: Content

    init(_ title: LocalizedStringKey, systemImage: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    /// A group with no title of its own: the section it is in has one.
    init(@ViewBuilder content: () -> Content) {
        self.title = nil
        self.systemImage = nil
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Group {
                    if let systemImage { Label(title, systemImage: systemImage) } else { Text(title) }
                }
                .font(.headline).foregroundStyle(.secondary).padding(.leading, 12)
            }
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
