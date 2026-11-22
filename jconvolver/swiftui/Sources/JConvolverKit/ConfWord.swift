// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The words of the configuration files: a name or a path that may be quoted. The reading follows `sstring.cc` of
/// jconvolver, so that a file means the same thing here as for the program.
public enum ConfWord {
    /// All the words of a text, as they are written after a command (the empty word is not kept); nil when the quoting is wrong.
    public static func split(_ text: String) -> [String]? {
        var rest = Substring(text), words: [String] = []
        while true {
            if rest.allSatisfy({ $0 == " " || $0 == "\t" }) { return words }
            guard let (word, next) = read(rest) else { return nil }
            if !word.isEmpty { words.append(word) }
            rest = next
        }
    }

    /// The words as a text that `split` reads back, one blank between them.
    public static func join(_ words: [String]) -> String { words.map { format($0) }.joined(separator: " ") }

    private static func isControl(_ c: Unicode.Scalar) -> Bool { c.value < 0x20 || c.value == 0x7f }

    /// Reads the first word of `text`: blanks before it are skipped, and it ends at a blank, at a control character or at
    /// the end of the text; between quotes (single or double) it may hold blanks, and a backslash makes the next
    /// character literal (except between single quotes).
    ///
    /// - Returns: the word and what follows it, or nil when there is no word or when the quoting is wrong (what `sstring`
    ///   refuses). The empty word, written `""`, is a word.
    public static func read(_ text: Substring) -> (word: String, rest: Substring)? {
        let s = text.unicodeScalars
        var i = s.startIndex
        var out = String.UnicodeScalarView()
        var escaped = false
        var quote: Unicode.Scalar?
        while true {
            // The end of the text counts as a control character, as the terminating zero does for sstring.
            guard i < s.endIndex else {
                if quote != nil || escaped { return nil }
                return out.isEmpty ? nil : (String(out), text[text.endIndex...])
            }
            var c = s[i]
            let next = s.index(after: i)
            if c == "\t" { c = " " }
            if isControl(c) {
                if quote != nil || escaped { return nil }
                return out.isEmpty ? nil : (String(out), Substring(s[i...]))
            }
            if escaped { out.append(c); escaped = false; i = next; continue }
            if c == "\\" {
                if quote == "'" { out.append(c) } else { escaped = true }
                i = next
                continue
            }
            if c == "'" || c == "\"" {
                if c == quote { return (String(out), Substring(s[next...])) }
                if quote != nil || !out.isEmpty { return nil }
                quote = c
                i = next
                continue
            }
            if c == " " {
                if quote != nil { out.append(c) } else if !out.isEmpty { return (String(out), Substring(s[i...])) }
                i = next
                continue
            }
            out.append(c)
            i = next
        }
    }

    /// The word as it is written in a file: as it is when that is safe, else between double quotes.
    public static func format(_ word: String) -> String {
        let scalars = word.unicodeScalars.map { isControl($0) ? " " : $0 }
        let plain = !scalars.isEmpty && !scalars.contains { $0 == " " || $0 == "'" || $0 == "\"" || $0 == "\\" }
        var out = ""
        if plain {
            out.unicodeScalars.append(contentsOf: scalars)
            return out
        }
        out = "\""
        for c in scalars {
            // Even a quote of the other kind must be escaped: sstring refuses it between quotes.
            if c == "\"" || c == "\\" || c == "'" { out += "\\" }
            out.unicodeScalars.append(c)
        }
        return out + "\""
    }
}
