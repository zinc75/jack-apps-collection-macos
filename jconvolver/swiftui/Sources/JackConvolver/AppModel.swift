// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import JConvolverKit
import Observation
import SoundFileKit
import SwiftUI
import UniformTypeIdentifiers

enum Page: String, CaseIterable, Identifiable {
    case home, matrix, ports, launch, log, display
    var id: String { rawValue }
}

/// What the program does: the real-time convolution on JACK, or the processing of a sound file.
enum RunMode: String {
    case realTime, file
}

/// The impulse responses as a matrix, or as a table.
enum ViewMode: String {
    case matrix, table
}

/// What the window needs: the configuration that is open, the engine, the state of JACK, and the page that is shown.
@MainActor
@Observable
final class AppModel {
    var page = Page.home { didSet { if page == .log { markLogSeen() } } }
    /// The lines of the journal up to this number have been looked at.
    private(set) var logSeen = 0
    var mode = RunMode.realTime { didSet { refreshProblems() } }
    var options = EngineCommand.Options()
    /// The files of the processing on sound files.
    var inputFile: URL? { didSet { refreshProblems() } }
    var outputFile: URL?

    private(set) var document: ConvDocument?
    /// What is selected in the matrix, how big its cells are drawn, and what the pointer is over.
    var selection = MatrixSelection()
    var cellSize: CGFloat = 26
    var hoverPair: ConvPair?
    /// Where what is being dragged would land, while it is dragged over the matrix.
    var dropPlan: PlacementPlan?
    var draggedItems: [Placeable] = []
    private(set) var history = DocumentHistory()
    /// The matrix or the table, and what the row above the table does: to all the impulse responses or the selected ones, replacing or shifting.
    var viewMode = ViewMode.matrix
    /// What was copied from the matrix.
    private(set) var clipboard: [ClipboardItem] = []
    var bulkOnSelection = false
    var bulkShifts = false
    /// The list of sound files beside the matrix: what is chosen in it, what is open, what is searched for.
    private(set) var binFiles: [BinFile] = []
    var picked: Set<Placeable> = []
    var binExpanded: Set<String> = []
    var binFilter = ""
    private(set) var fileURL: URL?
    private(set) var problems: [ConvProblem] = []
    private(set) var recents: [URL] = []
    /// What the application says in an alert.
    var message: String?
    var showsCommand = false
    var showsProblems = false
    var showsNewConfiguration = false
    var showsPortNames = false
    /// The impulse response whose detail window is open.
    var detail: DetailTarget?

    let controller = EngineController()
    let jack = JackStatus()
    @ObservationIgnored let catalog = SoundFileCatalog()
    @ObservationIgnored private let defaults: UserDefaults

    /// - Parameter defaults: where the settings are kept; nil for a throw-away store (the debug aids use it: they must not touch
    ///   what the person has set up).
    init(defaults: UserDefaults?) {
        self.defaults = defaults ?? UserDefaults(suiteName: "jackconvolver.debug.\(UUID().uuidString)") ?? .standard
        recents = (self.defaults.stringArray(forKey: "recentFiles") ?? []).map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func start() {
        jack.onXruns = { [weak self] count in
            for _ in 0..<count { self?.controller.recordXrun() }
        }
        jack.start()
    }

    func shutdown() {
        controller.stop()
        jack.stop()
    }

    func markLogSeen() { logSeen = (controller.log.entries.last?.id ?? -1) + 1 }

    func setBinFiles(_ files: [BinFile]) { binFiles = files }
    func setClipboard(_ items: [ClipboardItem]) { clipboard = items }

    // MARK: The configuration

    var isOpen: Bool { document != nil }
    var isEdited: Bool { document?.isModified ?? false }
    var name: String { fileURL?.lastPathComponent ?? String(localized: "sans titre.conf") }
    var configDirectory: String { fileURL?.deletingLastPathComponent().path ?? NSHomeDirectory() }

    func openPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "conf") ?? .plainText, .plainText]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "Choisissez un fichier de configuration de jconvolver.")
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }

    func open(_ url: URL) {
        guard let data = try? Data(contentsOf: url) else {
            message = String(localized: "Le fichier « \(url.lastPathComponent) » ne peut pas être lu.")
            return
        }
        let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        let (config, _) = ConvConfig.parse(text)
        let imported = ConvDocument.make(from: config)
        document = imported.document
        fileURL = url
        remember(url)
        resetEditing()
        refreshProblems()
        page = .matrix
        if config.convolver == nil {
            message = String(localized: "« \(url.lastPathComponent) » n'a pas de ligne /convolver/new : ce n'est pas une configuration de jconvolver.")
        }
    }

    func newConfiguration(inputs: Int, outputs: Int) {
        document = ConvDocument(inputs: inputs, outputs: outputs)
        fileURL = nil
        resetEditing()
        refreshProblems()
        page = .matrix
    }

    /// Changes the matrix, and keeps the change in the history. Everything that depends on it is worked out again.
    func edit(_ label: String, _ change: (inout ConvDocument) -> Void) {
        guard var d = document else { return }
        let before = d
        change(&d)
        guard d != before else { return }
        history.record(label, before: before)
        document = d
        documentChanged()
    }

    private func documentChanged() {
        if let document { selection.clamp(inputs: document.inputCount, outputs: document.outputCount) }
        refreshProblems()
    }

    private func resetEditing() {
        history.clear()
        selection = MatrixSelection()
        hoverPair = nil
        dropPlan = nil
        picked = []
        binExpanded = []
        binFilter = ""
        loadBin()
    }

    var canUndo: Bool { history.canUndo }
    var canRedo: Bool { history.canRedo }

    func undo() {
        guard let document, let step = history.undo(current: document) else { return }
        self.document = step.document
        documentChanged()
    }

    func redo() {
        guard let document, let step = history.redo(current: document) else { return }
        self.document = step.document
        documentChanged()
    }

    /// The text of the configuration file as it would be written now.
    var configText: String { document.map { $0.makeConfig(automatic: automaticHeader).text } ?? "" }

    @discardableResult
    func save(asNew: Bool = false) -> Bool {
        guard let document else { return false }
        var target = fileURL
        if asNew || target == nil {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [UTType(filenameExtension: "conf") ?? .plainText]
            panel.nameFieldStringValue = fileURL?.lastPathComponent ?? "configuration.conf"
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let url = panel.url else { return false }
            target = url
        }
        guard let target else { return false }
        let config = document.makeConfig(automatic: automaticHeader)
        do {
            try config.text.write(to: target, atomically: true, encoding: .utf8)
        } catch {
            message = String(localized: "Le fichier ne peut pas être enregistré : \(error.localizedDescription)")
            return false
        }
        var saved = document
        saved.markSaved(as: config)
        self.document = saved
        fileURL = target
        remember(target)
        return true
    }

    private func remember(_ url: URL) {
        recents.removeAll { $0 == url }
        recents.insert(url, at: 0)
        recents = Array(recents.prefix(8))
        defaults.set(recents.map(\.path), forKey: "recentFiles")
    }

    // MARK: What is wrong

    /// The numbers of `/convolver/new` that the person did not set: worked out from the period of JACK and the files.
    var automaticHeader: ConvHeader {
        document?.automaticHeader(period: jack.bufferSize ?? 256, lengthOfFile: lengthOfFile) ?? ConvHeader(partition: 256, maxLength: 1)
    }

    private var lengthOfFile: (ConvImpulse) -> Int? {
        let catalog = catalog, directory = configDirectory
        return { impulse in
            guard case .file(let file, _) = impulse.source else { return nil }
            return catalog.info(at: ConvConfig.path(of: file, directory: impulse.directory, configDirectory: directory)).map { Int($0.frames) }
        }
    }

    func refreshProblems() {
        guard let document else { problems = []; return }
        let catalog = catalog
        let context = ConvValidationContext(
            mode: mode == .realTime ? .realTime(jackRate: jack.sampleRate)
                                    : .file(input: inputFile.flatMap { catalog.info(at: $0.path) }),
            configDirectory: configDirectory,
            latencyCompensation: options.latencyCompensation,
            fileInfo: { catalog.info(at: $0) })
        problems = ConvValidator.problems(in: document, context: context)
    }

    var hasErrors: Bool { problems.contains { $0.severity == .error } }

    // MARK: Running

    /// The command as it is shown: with the file of the person, not the temporary copy that runs when the matrix has been changed.
    var displayedCommand: EngineCommand? {
        guard isOpen else { return nil }
        return makeCommand(configPath: fileURL?.path ?? name)
    }

    private func makeCommand(configPath: String) -> EngineCommand {
        switch mode {
        case .realTime:
            return EngineCommand(program: .jconvolver, options: options, configPath: configPath)
        case .file:
            return EngineCommand(program: .fconvolver, options: options, configPath: configPath,
                                 inputFile: inputFile?.path ?? "", outputFile: outputFile?.path ?? "")
        }
    }

    /// A start while the engine is stopped, a stop while it runs.
    func toggleRun() {
        if controller.isRunning { controller.stop(); return }
        guard isOpen, !hasErrors else { showsProblems = hasErrors; return }
        do {
            let path = try runConfigPath()
            let command = makeCommand(configPath: path)
            guard let executable = EngineHelper.executableURL(for: command.program) else {
                message = String(localized: "Le programme \(command.program.rawValue) est introuvable.")
                return
            }
            controller.acknowledgeEnd()
            try controller.start(command, executable: executable)
        } catch {
            message = String(localized: "Le moteur ne peut pas démarrer : \(error.localizedDescription)")
        }
    }

    /// The file the program reads: the file of the person when it was not changed, else a copy written in the temporary folder.
    /// The copy starts with a `/cd` to the folder of the original, so that the files named without a path are found.
    private func runConfigPath() throws -> String {
        if !isEdited, let fileURL { return fileURL.path }
        guard let document else { throw CocoaError(.fileNoSuchFile) }
        var config = document.makeConfig(automatic: automaticHeader)
        config.lines.insert(ConfLine(.changeDirectory(configDirectory)), at: 0)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("JackConvolver", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("\(UUID().uuidString).conf")
        try config.text.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }
}
