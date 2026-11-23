// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import JackBridge
import JConvolverKit
import Observation
import PlotKit
import SoundFileKit
import SwiftUI
import UniformTypeIdentifiers

enum Page: String, CaseIterable, Identifiable {
    case home, matrix, impulse, ports, launch, log, display
    var id: String { rawValue }
}

/// What the program does: the real-time convolution on JACK, or the processing of a sound file.
enum RunMode: String {
    case realTime, file
}

/// What an inspect button does when responses are already drawn: ask, add the new one to them, or draw it alone.
enum InspectChoice: String, CaseIterable {
    case ask, add, replace
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
    var mode = RunMode.realTime {
        didSet {
            refreshProblems()
            // The pages of the launch and of the JACK connections are for the engine in real time: on sound files the processing has its
            // window, and there is no JACK.
            if mode == .file, page == .launch || page == .ports { page = .matrix }
        }
    }
    /// The window of the processing of a sound file.
    var showsRender = false
    /// The window of the configuration file (the name of the file in the footer opens it).
    var showsConfigFile = false
    var options = EngineCommand.Options()
    /// The files of the processing on sound files.
    var inputFile: URL? {
        didSet {
            // A name for the result as soon as there is an input: next to it, with _conv after its name. The person can change it.
            if let inputFile, outputFile == nil {
                outputFile = inputFile.deletingLastPathComponent()
                    .appendingPathComponent(inputFile.deletingPathExtension().lastPathComponent + "_conv.wav")
            }
            refreshProblems()
        }
    }
    var outputFile: URL?
    /// The run that is going on or has just ended: how many have been started, when this one started, and how long it took.
    private(set) var runCount = 0

    private(set) var document: ConvDocument? { didSet { pruneTraces() } }
    /// What is selected in the matrix, how big its cells are drawn, and what the pointer is over.
    var selection = MatrixSelection()
    var cellSize: CGFloat = 26
    /// The size of a cell that makes the matrix fill the block it is in, and whether the person chose another one (pinch, command and
    /// scroll): the matrix follows the size of the window until then.
    var fitCellSize: CGFloat = 26
    var zoomIsManual = false
    /// The pointer is somewhere in the block of the matrix (not only above the cells): where the wheel zooms.
    var pointerInMatrixBlock = false

    /// Goes back to the size that fills the block.
    func resetZoom() { zoomIsManual = false; cellSize = fitCellSize }

    /// Zooms by a factor (a pinch, the wheel). A size that is the one that fits goes back to following the window.
    func zoom(by factor: CGFloat) {
        cellSize = min(max(cellSize * factor, 6), 80)
        zoomIsManual = true
    }

    func endZoom() {
        if abs(cellSize - fitCellSize) < 0.75 { resetZoom() }
    }
    var hoverPair: ConvPair?
    /// Where the pointer is above the matrix, in the coordinates of the matrix (for the card that follows it).
    var hoverPoint: CGPoint?
    /// A selection is being made (a drag on the matrix, or command or shift held down): the card is not shown, it would be in the way.
    var isSelecting = false
    var selectionKeyDown = false
    /// Where what is being dragged would land, while it is dragged over the matrix.
    var dropPlan: PlacementPlan?
    var draggedItems: [Placeable] = []
    /// Dragging from the list of files to the matrix is done by the application (the system drag and drop does not work well here): the
    /// pointer, in the coordinates of the page of the matrix, while something is dragged; and where the matrix is in those coordinates.
    var dragPointer: CGPoint?
    /// What is dragged cannot be dropped where the pointer is (several things on several chosen cells).
    var dropBlocked = false
    /// What is dragged is above the panel under the matrix: it would go to the cells that are chosen.
    var dropOnPanel = false
    var selectionPanelFrame: CGRect = .zero
    var matrixViewport: CGRect = .zero
    var matrixContentFrame: CGRect = .zero
    private(set) var history = DocumentHistory()
    /// The matrix or the table, and what the row above the table does: to all the impulse responses or the selected ones, replacing or shifting.
    var viewMode = ViewMode.matrix
    /// What was copied from the matrix.
    private(set) var clipboard: [ClipboardItem] = []
    /// Where what was copied came from (it stays outlined in the matrix until something else is copied) and how big it is.
    private(set) var clipboardShape: MatrixSelection.Shape?
    private(set) var clipboardSize: (inputs: Int, outputs: Int) = (0, 0)
    var bulkOnSelection = false
    var bulkShifts = false
    /// The list of sound files beside the matrix: what is chosen in it, what is open, what is searched for.
    private(set) var binFiles: [BinFile] = []
    /// The files the person took out of the list: they stay out until the folder is read again or another configuration is opened (a file the
    /// matrix uses cannot be taken out).
    var binExcluded: Set<String> = []
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
    /// Which side the page of the connections shows: the inputs (from JACK to jconvolver) or the outputs.
    var connectionSide: PortSide = .input
    /// The connections made to the running program, as the configuration says: what the page of the connections changes is
    /// made at once, and these are what to take away when a connection is removed.
    @ObservationIgnored var appliedLinks: Set<JackLink> = []
    /// While the engine runs, the configuration is only looked at: nothing of it can be changed (the engine read it once, at its start).
    var isLocked: Bool { controller.isRunning }
    /// The connections as they are while the engine runs in real time: they are made in JACK at once and do not change the configuration.
    /// A copy of the configuration that only the page of the connections reads and changes.
    var liveWiring: ConvDocument?
    /// What the connections were when the engine stopped, if they differ from the file: the person is asked whether to write them there.
    var pendingWiring: ConvDocument?
    var showsApplyWiring = false
    var showsResize = false
    var showsGestures = false
    /// The impulse responses drawn on the page of the analysis, in the order they were added, and the one of them that is edited (its zone, its
    /// markers, the inspector). A trace is a place of the matrix, not a file: one file can be placed twice, with other settings.
    var traces: [DetailTarget] = []
    var detail: DetailTarget?
    /// What a click on an inspect button does when other responses are already drawn.
    var inspectChoice = InspectChoice(rawValue: UserDefaults.standard.string(forKey: "inspectChoice") ?? "") ?? .ask {
        didSet { UserDefaults.standard.set(inspectChoice.rawValue, forKey: "inspectChoice") }
    }
    /// The state of the plots of that page, which its tools in the toolbar of the window and its inspector share.
    let plotController = PlotController()

    let controller = EngineController()
    let jack = JackStatus()
    @ObservationIgnored let catalog = SoundFileCatalog()
    @ObservationIgnored private let defaults: UserDefaults

    /// Whether the card with what is on a cell shows above the matrix, under the pointer. Kept between launches.
    var showsHoverCard = true {
        didSet { defaults.set(showsHoverCard, forKey: "showsHoverCard") }
    }

    /// - Parameter defaults: where the settings are kept; nil for a throw-away store (the debug aids use it: they must not touch
    ///   what the person has set up).
    init(defaults: UserDefaults?) {
        self.defaults = defaults ?? UserDefaults(suiteName: "jackconvolver.debug.\(UUID().uuidString)") ?? .standard
        showsHoverCard = self.defaults.object(forKey: "showsHoverCard") as? Bool ?? true
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
    /// The dashed outline goes away once what was copied is pasted; what was copied can still be pasted again.
    func clearClipboardOutline() { clipboardShape = nil }

    func setClipboard(_ items: [ClipboardItem], shape: MatrixSelection.Shape? = nil, size: (inputs: Int, outputs: Int) = (0, 0)) {
        clipboard = items
        clipboardShape = items.isEmpty ? nil : shape
        clipboardSize = size
    }

    // MARK: The configuration

    var isOpen: Bool { document != nil }
    var isEdited: Bool { document?.isModified ?? false }
    /// The name of a configuration that has not been saved: shown in the footer and proposed when it is saved. No space in it.
    var defaultFileName: String { String(localized: "sans_titre") + ".conf" }
    var name: String { fileURL?.lastPathComponent ?? defaultFileName }
    /// A configuration that was never saved has no file to save to: it is saved under a name.
    var savesAsNew: Bool { fileURL == nil }
    var configDirectory: String { fileURL?.deletingLastPathComponent().path ?? NSHomeDirectory() }

    func openPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "conf") ?? .plainText]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "Choisissez un fichier de configuration de jconvolver.")
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }

    func open(_ url: URL) {
        guard !isLocked else { message = String(localized: "Arrêtez le moteur avant d'ouvrir une autre configuration."); return }
        guard let data = try? Data(contentsOf: url) else {
            message = String(localized: "Le fichier « \(url.lastPathComponent) » ne peut pas être lu.")
            return
        }
        let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        let (config, _) = ConvConfig.parse(text)
        // Something that is not a configuration of jconvolver (it has no /convolver/new line) is not opened: nothing changes.
        guard config.convolver != nil else {
            message = String(localized: "« \(url.lastPathComponent) » n'a pas de ligne /convolver/new : ce n'est pas une configuration de jconvolver.")
            return
        }
        let imported = ConvDocument.make(from: config)
        document = imported.document
        fileURL = url
        remember(url)
        resetEditing()
        refreshProblems()
        page = .matrix
    }

    func newConfiguration(inputs: Int, outputs: Int) {
        guard !isLocked else { message = String(localized: "Arrêtez le moteur avant de créer une autre configuration."); return }
        document = ConvDocument(inputs: inputs, outputs: outputs)
        fileURL = nil
        resetEditing()
        refreshProblems()
        page = .matrix
    }

    /// Changes the matrix, and keeps the change in the history. Everything that depends on it is worked out again.
    func edit(_ label: String, _ change: (inout ConvDocument) -> Void) {
        guard !isLocked, var d = document else { return }
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
        syncConnections()
    }

    private func resetEditing() {
        traces = []
        detail = nil
        history.clear()
        zoomIsManual = false
        setClipboard([])
        selection = MatrixSelection()
        hoverPair = nil
        dropPlan = nil
        picked = []
        binExpanded = []
        binFilter = ""
        binExcluded = []
        loadBin()
    }

    var canUndo: Bool { !isLocked && history.canUndo }
    var canRedo: Bool { !isLocked && history.canRedo }

    func undo() {
        guard !isLocked, let document, let step = history.undo(current: document) else { return }
        self.document = step.document
        documentChanged()
    }

    func redo() {
        guard !isLocked, let document, let step = history.redo(current: document) else { return }
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
            panel.nameFieldStringValue = fileURL?.lastPathComponent ?? defaultFileName
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

    /// Takes a file off the list of recent ones (the file itself is left alone).
    func forgetRecent(_ url: URL) {
        recents.removeAll { $0 == url }
        defaults.set(recents.map(\.path), forKey: "recentFiles")
    }

    func clearRecents() {
        recents = []
        defaults.set([String](), forKey: "recentFiles")
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
        // On sound files the round button opens the window of the processing, where everything is, and where the result is shown.
        if mode == .file {
            if isOpen { showsRender = true }
            return
        }
        if controller.isRunning { controller.stop(); return }
        startRun()
    }

    /// Starts the program (what the button "Traiter" of the window does on sound files).
    func startRun() {
        guard isOpen, !hasErrors else { showsProblems = hasErrors; return }
        do {
            let path = try runConfigPath()
            let command = makeCommand(configPath: path)
            guard let executable = EngineHelper.executableURL(for: command.program) else {
                message = String(localized: "Le programme \(command.program.rawValue) est introuvable.")
                return
            }
            controller.acknowledgeEnd()
            runCount += 1
            try controller.start(command, executable: executable)
            liveWiring = mode == .realTime ? document : nil
            appliedLinks = mode == .realTime ? wantedLinks : []
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
