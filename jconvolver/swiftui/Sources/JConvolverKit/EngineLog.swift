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

    /// What the application and JACK say, without words: the interface writes them in the language of the person. The
    /// lines of the program are not notes; they are shown as the program wrote them.
    public enum Note: Equatable, Sendable {
        /// A run starts, with its command line.
        case launch(commandLine: String)
        /// The program could not be started.
        case cannotLaunch(reason: String)
        /// The person asked the program to end.
        case stopRequested
        /// The program ended, with its exit code.
        case ended(program: String, status: Int32)
        /// An audio cut that JACK reported, with how late the cycle was.
        case xrun(microseconds: Int)
        /// A sound file was written.
        case fileWritten(name: String)

        /// The words in English, for the tests and for a copy of the journal.
        public var englishText: String {
            switch self {
            case .launch(let line): return "Launch: \(line)"
            case .cannotLaunch(let reason): return "Cannot start the program: \(reason)"
            case .stopRequested: return "Stop requested (SIGINT)"
            case .ended(let program, let status): return "\(program) ended (code \(status))"
            case .xrun(let us): return "xrun: \(us) µs late"
            case .fileWritten(let name): return "File written: \(name)"
            }
        }
    }

    public let id: Int
    public var date: Date
    public var source: Source
    public var severity: Severity
    /// The line of the program, or the note in English.
    public var text: String
    /// What the application or JACK says, when it is not a line of the program.
    public var note: Note?
    /// A line that opens a run, which separates it from the one before.
    public var startsRun: Bool

    public init(id: Int, date: Date = Date(), source: Source, severity: Severity = .info, text: String, note: Note? = nil, startsRun: Bool = false) {
        self.id = id
        self.date = date
        self.source = source
        self.severity = severity
        self.text = text
        self.note = note
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

    /// What the application or JACK says.
    public mutating func append(note: EngineLogEntry.Note, source: EngineLogEntry.Source = .app, severity: EngineLogEntry.Severity = .info,
                                startsRun: Bool = false, date: Date = Date()) {
        entries.append(EngineLogEntry(id: nextID, date: date, source: source, severity: severity, text: note.englishText, note: note, startsRun: startsRun))
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
