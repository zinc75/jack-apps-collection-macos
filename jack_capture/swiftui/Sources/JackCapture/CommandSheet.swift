// SPDX-License-Identifier: GPL-2.0-or-later

import SwiftUI
import JackCaptureKit

/// The command the application would run, to copy into a terminal.
struct CommandSheet: View {
    @Environment(RecorderModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        let text = model.command.displayText
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Ligne de commande générée").font(.title3).fontWeight(.semibold)
                Text("Ce que l'application lance, à copier dans un terminal.").foregroundStyle(.secondary)
            }
            ScrollView {
                Text(CommandHighlighter.attributed(text))
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(minHeight: 120, maxHeight: 280)
            .background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.12), lineWidth: 0.5))
            HStack {
                Spacer()
                Button(copied ? "Copié" : "Copier") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    copied = true
                }
                Button("Fermer") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560)
    }
}

/// Colours of the terminal view: the program and its sub-commands, the options, the values and
/// the comments. The area is dark in both appearances, so the colours do not depend on the theme.
enum CommandHighlighter {
    private static let commands: Set<String> = ["jack_capture", "jack_connect", "cd"]
    private static let token = try! NSRegularExpression(pattern: #"(?:"(?:[^"\\]|\\.)*"|\\.|[^\s"\\]+)+"#)

    static func attributed(_ text: String) -> AttributedString {
        var out = AttributedString()
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        for (i, line) in lines.enumerated() {
            if i > 0 { out += AttributedString("\n") }
            let line = String(line)
            if line.hasPrefix("#") {
                var a = AttributedString(line)
                a.foregroundColor = Color(red: 0.56, green: 0.56, blue: 0.58)
                out += a
                continue
            }
            let ns = line as NSString
            var cursor = 0
            for m in token.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
                if m.range.location > cursor {
                    out += AttributedString(ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor)))
                }
                let word = ns.substring(with: m.range)
                var a = AttributedString(word)
                a.foregroundColor = commands.contains(word) ? Color(red: 0.54, green: 0.58, blue: 1.0)
                    : word.hasPrefix("-") ? Color(red: 0.96, green: 0.65, blue: 0.26)
                    : Color(red: 0.31, green: 0.83, blue: 0.50)
                out += a
                cursor = m.range.location + m.range.length
            }
            if cursor < ns.length { out += AttributedString(ns.substring(from: cursor)) }
        }
        return out
    }
}
