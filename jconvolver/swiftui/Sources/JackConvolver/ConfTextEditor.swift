// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import JConvolverKit
import SwiftUI

/// An editor of the text of a configuration: a monospaced text with the numbers of its lines, the colours of the commands, and the lines that have a
/// problem tinted (red for what jconvolver would refuse or could not read, orange for what only deserves a look), with a mark in the margin.
struct ConfTextEditor: NSViewRepresentable {
    @Binding var text: String
    var problems: [ConfLineProblem]
    var isEditable: Bool
    /// A line (from 1) to go to: the cursor is put at its start and it is brought into view. Set back to nil once it is done.
    @Binding var jump: Int?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = NSColor(white: 0.11, alpha: 1)
        scroll.wantsLayer = true
        scroll.layer?.cornerRadius = 8
        scroll.layer?.masksToBounds = true
        let textView = scroll.documentView as! NSTextView
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.backgroundColor = NSColor(white: 0.11, alpha: 1)
        textView.textColor = NSColor(white: 0.9, alpha: 1)
        textView.insertionPointColor = .white
        textView.drawsBackground = true
        // Quotes and dashes of a configuration are the plain ones: nothing is replaced by what looks better.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        // The text wraps at the width of the view, as the standard view of text does: a long line stays one line (one number in the margin).
        textView.textContainerInset = NSSize(width: 4, height: 8)
        let ruler = LineNumberRuler(textView: textView)
        scroll.verticalRulerView = ruler
        scroll.hasVerticalRuler = true
        scroll.rulersVisible = true
        context.coordinator.textView = textView
        context.coordinator.ruler = ruler
        textView.string = text
        context.coordinator.restyle(problems: problems)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let c = context.coordinator
        c.parent = self
        guard let textView = c.textView else { return }
        textView.isEditable = isEditable
        if textView.string != text {
            let selection = textView.selectedRange()
            textView.string = text
            textView.setSelectedRange(NSRange(location: min(selection.location, (text as NSString).length), length: 0))
            // The text was replaced from outside (applied, or a step of the history): what was typed before cannot be undone onto it.
            textView.undoManager?.removeAllActions()
        }
        c.restyle(problems: problems)
        if let line = jump {
            c.go(to: line)
            DispatchQueue.main.async { jump = nil }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ConfTextEditor
        weak var textView: NSTextView?
        weak var ruler: LineNumberRuler?
        private var styledText: String?
        private var styledProblems: [ConfLineProblem] = []

        init(_ parent: ConfTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            if parent.text != textView.string { parent.text = textView.string }
            restyle(problems: parent.problems)
        }

        /// The colours of the text, and the tint of the lines that have a problem.
        func restyle(problems: [ConfLineProblem]) {
            guard let textView, let storage = textView.textStorage, let layout = textView.layoutManager else { return }
            let text = textView.string
            if styledText != text {
                styledText = text
                let ns = text as NSString
                let whole = NSRange(location: 0, length: ns.length)
                storage.beginEditing()
                storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular), range: whole)
                storage.addAttribute(.foregroundColor, value: NSColor(white: 0.9, alpha: 1), range: whole)
                ns.enumerateSubstrings(in: whole, options: [.byLines, .substringNotRequired]) { _, range, _, _ in
                    Self.color(line: ns.substring(with: range) as NSString, at: range.location, in: storage)
                }
                storage.endEditing()
            }
            styledProblems = problems
            let whole = NSRange(location: 0, length: (text as NSString).length)
            layout.removeTemporaryAttribute(.backgroundColor, forCharacterRange: whole)
            let starts = Self.lineStarts(text)
            for p in problems where p.line >= 1 && p.line <= starts.count {
                let start = starts[p.line - 1]
                let end = p.line < starts.count ? starts[p.line] : (text as NSString).length
                let tint = p.isError ? NSColor.systemRed.withAlphaComponent(0.22) : NSColor.systemOrange.withAlphaComponent(0.18)
                layout.addTemporaryAttribute(.backgroundColor, value: tint, forCharacterRange: NSRange(location: start, length: max(end - start, 0)))
            }
            ruler?.problems = problems
            ruler?.text = text
            ruler?.needsDisplay = true
        }

        /// The offsets where the lines start.
        static func lineStarts(_ text: String) -> [Int] {
            let ns = text as NSString
            var starts = [0]
            var i = 0
            while i < ns.length {
                let line = ns.lineRange(for: NSRange(location: i, length: 0))
                i = NSMaxRange(line)
                if i < ns.length { starts.append(i) }
            }
            return starts
        }

        private static func color(line: NSString, at offset: Int, in storage: NSTextStorage) {
            let comment = NSColor(red: 0.56, green: 0.56, blue: 0.58, alpha: 1)
            let command = NSColor(red: 0.54, green: 0.58, blue: 1.0, alpha: 1)
            let value = NSColor(red: 0.31, green: 0.83, blue: 0.50, alpha: 1)
            if line.hasPrefix("#") {
                storage.addAttribute(.foregroundColor, value: comment, range: NSRange(location: offset, length: line.length))
                return
            }
            var position = 0, first = true
            while position < line.length {
                if line.character(at: position) == 32 { position += 1; continue }
                var end = position
                if line.character(at: position) == 34 {
                    end = position + 1
                    while end < line.length, line.character(at: end) != 34 { end += 1 }
                    end = min(end + 1, line.length)
                } else {
                    while end < line.length, line.character(at: end) != 32 { end += 1 }
                }
                let word = line.substring(with: NSRange(location: position, length: end - position))
                let color: NSColor?
                if first, word.hasPrefix("/") { color = command }
                else if word.hasPrefix("\"") || word.contains("/") || (word.contains(".") && Double(word) == nil) { color = value }
                else { color = nil }
                if let color { storage.addAttribute(.foregroundColor, value: color, range: NSRange(location: offset + position, length: end - position)) }
                position = end
                first = false
            }
        }

        /// The cursor to the start of a line, which is brought into view.
        func go(to line: Int) {
            guard let textView else { return }
            let starts = Self.lineStarts(textView.string)
            guard line >= 1, line <= starts.count else { return }
            let range = NSRange(location: starts[line - 1], length: 0)
            textView.window?.makeFirstResponder(textView)
            textView.setSelectedRange(range)
            textView.scrollRangeToVisible(range)
        }
    }
}

/// The margin of the editor: the number of each line, and a mark on the lines that have a problem.
final class LineNumberRuler: NSRulerView {
    var problems: [ConfLineProblem] = []
    var text = ""
    private weak var textView: NSTextView?

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 48
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: NSText.didChangeNotification, object: textView)
        if let clip = textView.enclosingScrollView?.contentView {
            clip.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: NSView.boundsDidChangeNotification, object: clip)
        }
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func refresh() { needsDisplay = true }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView, let layout = textView.layoutManager, let container = textView.textContainer else { return }
        // Only the margin itself: the rectangle to draw can be the whole of the view that holds it.
        NSColor(white: 0.15, alpha: 1).setFill()
        bounds.fill()
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
                                                         .foregroundColor: NSColor(white: 0.55, alpha: 1)]
        let visible = layout.glyphRange(forBoundingRect: textView.visibleRect, in: container)
        let ns = textView.string as NSString
        let starts = ConfTextEditor.Coordinator.lineStarts(textView.string)
        let byLine = Dictionary(problems.map { ($0.line, $0) }, uniquingKeysWith: { a, b in a.isError ? a : b })
        let origin = textView.textContainerOrigin.y - textView.visibleRect.origin.y
        var glyph = visible.location
        while glyph < NSMaxRange(visible) {
            let characterIndex = layout.characterIndexForGlyph(at: glyph)
            var fragmentRange = NSRange()
            let rectInView = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &fragmentRange)
            // A line number goes with the first fragment of a line (the next fragments of a line that wraps have none).
            if let line = Self.line(at: characterIndex, in: starts), starts[line - 1] == characterIndex {
                let y = rectInView.minY + origin
                let label = "\(line)" as NSString
                let size = label.size(withAttributes: attributes)
                label.draw(at: NSPoint(x: ruleThickness - size.width - 8, y: y + (rectInView.height - size.height) / 2), withAttributes: attributes)
                if let problem = byLine[line] {
                    (problem.isError ? NSColor.systemRed : NSColor.systemOrange).setFill()
                    NSBezierPath(ovalIn: NSRect(x: 8, y: y + (rectInView.height - 7) / 2, width: 7, height: 7)).fill()
                }
            }
            glyph = NSMaxRange(fragmentRange)
        }
        _ = ns
    }

    private static func line(at offset: Int, in starts: [Int]) -> Int? {
        var low = 0, high = starts.count - 1, found = 0
        while low <= high {
            let mid = (low + high) / 2
            if starts[mid] <= offset { found = mid; low = mid + 1 } else { high = mid - 1 }
        }
        return found + 1
    }
}
