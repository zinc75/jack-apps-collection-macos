// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// One line of the journal.
public struct EngineLogEntry: Identifiable, Equatable, Sendable {
    /// Who says it.
    public enum Source: String, Sendable {
        /// The program itself, as it wrote it.
        case engine
        /// What JACK reports to the application (xruns, the client connected).
        case jack
        /// What the application did: the launch, the stop, the end.
        case app
    }

    public enum Severity: Int, Comparable, Sendable {
        case info, warning, error
        public static func < (a: Severity, b: Severity) -> Bool { a.rawValue < b.rawValue }
    }

    public let id: Int
    public var date: Date
    public var source: Source
    public var severity: Severity
    public var text: String
    /// A line that opens a run, which separates it from the one before.
    public var startsRun: Bool

    public init(id: Int, date: Date = Date(), source: Source, severity: Severity = .info, text: String, startsRun: Bool = false) {
        self.id = id
        self.date = date
        self.source = source
        self.severity = severity
        self.text = text
        self.startsRun = startsRun
    }
}

/// What the program wrote, what JACK reported and what the application did, in the order it happened.
public struct EngineLog: Equatable, Sendable {
    public private(set) var entries: [EngineLogEntry] = []
    private var nextID = 0
    /// How many lines are kept; the oldest go first.
    public var capacity = 5_000

    public init() {}

    public mutating func append(source: EngineLogEntry.Source, severity: EngineLogEntry.Severity = .info, _ text: String,
                                startsRun: Bool = false, date: Date = Date()) {
        entries.append(EngineLogEntry(id: nextID, date: date, source: source, severity: severity, text: text, startsRun: startsRun))
        nextID += 1
        if entries.count > capacity { entries.removeFirst(entries.count - capacity) }
    }

    /// What a program wrote.
    public mutating func append(_ message: EngineMessage, date: Date = Date()) {
        let severity: EngineLogEntry.Severity = message.severity == .error ? .error : message.severity == .warning ? .warning : .info
        append(source: .engine, severity: severity, message.text, date: date)
    }

    public mutating func clear() { entries.removeAll() }

    public var warningCount: Int { entries.filter { $0.severity == .warning }.count }
    public var errorCount: Int { entries.filter { $0.severity == .error }.count }

    /// The lines to show: all of them, or only the warnings and the errors (the opening line of each run always stays).
    public func entries(onlyProblems: Bool) -> [EngineLogEntry] {
        onlyProblems ? entries.filter { $0.startsRun || $0.severity >= .warning } : entries
    }

    /// The text to copy, one line per entry.
    public func plainText(onlyProblems: Bool = false) -> String {
        let format = Date.FormatStyle().hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits)
        return entries(onlyProblems: onlyProblems).map { "\($0.date.formatted(format))  \($0.source.rawValue)  \($0.text)" }.joined(separator: "\n")
    }
}
