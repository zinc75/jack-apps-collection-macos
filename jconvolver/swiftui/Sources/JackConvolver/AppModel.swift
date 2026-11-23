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
    case home, matrix, impulse, ports, launch, config, log, display
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
    /// The name the engine was given as a JACK client for its last run (the one of the configuration unless another engine had it).
    private(set) var runClientName: String?
    /// The clients that JACK had when the engine was started: one that is not among them, while the name of the engine is not known yet, is the engine.
    @ObservationIgnored private var clientsBeforeStart: Set<String> = []
    private(set) var problems: [ConvProblem] = []
    /// What the application says in an alert.
    var message: String?
    var showsCommand = false
    var showsProblems = false
    /// Where files that the configuration cannot find may be found again (next to the configuration file), and the sheet that proposes it.
    var pathProposals: [PathProposal] = []
    var showsResolver = false
    var showsPortable = false
    /// The fade typed for the response that is edited, in samples: a draft, shown on the plots, until it is applied (a new file is then written).
    var fadeIn = 0
    var fadeOut = 0
    var showsFade = false
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
    /// Set when the person closed the window and said that the engine goes on: the session stays, without a window.
    @ObservationIgnored var keepsRunning = false
    /// Whether a window has shown this session (a session that is being opened has none yet, and is not a hidden one).
    @ObservationIgnored private(set) var shownOnce = false
    /// The name of the file that is being brought to the expected rate (nil when no conversion runs).
    var conversionName: String?
    var showsResize = false
    var showsGestures = false
    /// The impulse responses drawn on the page of the analysis, in the order they were added, and the one of them that is edited (its zone, its
    /// markers, the inspector). A trace is a place of the matrix, not a file: one file can be placed twice, with other settings.
    var traces: [DetailTarget] = []
    /// Files drawn with the traces for comparison, that are not a place of the matrix (the original of a file that was converted): read only.
    var references: [ReferenceTrace] = []
    /// The page that the analysis was opened from: closing the analysis goes back there.
    var analysisOrigin: Page?
    /// A conversion that is being looked at against its original: it can be kept or refused.
    var pendingConversion: PendingConversion?
    var detail: DetailTarget?
    /// The state of the plots of that page, which its tools in the toolbar of the window and its inspector share.
    let plotController = PlotController()

    let controller = EngineController()
    /// What the windows share: JACK, the sound files that are known, the recent files and the settings.
    let hub: AppHub
    /// What tells this session from the others: the window that shows it is opened for it.
    let id: UUID
    @ObservationIgnored let created = Date()
    /// The window that shows this session, to bring it forward.
    @ObservationIgnored weak var window: NSWindow? {
        didSet { if window != nil { shownOnce = true } }
    }
    /// Whether the window of this session is not there to be seen: closed (the engine goes on), minimized or hidden.
    var isWindowHidden: Bool {
        guard shownOnce else { return false }
        guard let window else { return true }
        return window.isMiniaturized || !window.isVisible
    }
    /// A configuration opened as a copy of a file that is open in another window: it has no file of its own until it is saved, and reads the files it names
    /// from the folder of the original.
    private(set) var originFolder: URL?
    private var copyName: String?
    /// The name of the file this one is a copy of, when it is one.
    private(set) var copyOf: String?

    var jack: JackStatus { hub.jack }
    @ObservationIgnored var catalog: SoundFileCatalog { hub.catalog }
    var recents: [URL] { hub.recents }
    var showsHoverCard: Bool {
        get { hub.showsHoverCard }
        set { hub.showsHoverCard = newValue }
    }
    /// What a click on an inspect button does when other responses are already drawn.
    var inspectChoice: InspectChoice {
        get { hub.inspectChoice }
        set { hub.inspectChoice = newValue }
    }

    init(hub: AppHub, id: UUID = UUID()) {
        self.hub = hub
        self.id = id
    }

    /// Brings the window of this session in front of the others.
    func showWindow() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func start() { hub.start() }

    /// Stops the engine of this session.
    func shutdown() { controller.stop() }

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
    /// Whether this session is a copy of a file that another window has open: it has no file of its own until it is saved.
    var isCopy: Bool { fileURL == nil && copyOf != nil }
    /// The name shown for the configuration: its file, the name it will be saved under if it is a copy, else "Sans titre".
    var displayName: String { fileURL?.lastPathComponent ?? copyName ?? String(localized: "Sans titre") }
    /// The file of the configuration, changed by a rename (the file itself is renamed on the disk).
    func setFileURL(_ url: URL) { fileURL = url }
    /// A configuration that was never saved has no file to save to: it is saved under a name.
    var savesAsNew: Bool { fileURL == nil }
    var configDirectory: String { fileURL?.deletingLastPathComponent().path ?? originFolder?.path ?? NSHomeDirectory() }

    func openPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "conf") ?? .plainText]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "Choisissez un fichier de configuration de jconvolver.")
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }

    /// Opens a configuration: here when the window has none, else where the person says (a new session, or in place of the one that is open).
    func open(_ url: URL) { hub.open(url, from: self) }

    /// Reads the configuration in this session. `asCopy`: the file is open in another window, this one is a copy with no file of its own.
    func load(_ url: URL, asCopy: Bool = false) {
        guard !isLocked else { message = String(localized: "Arrêtez le moteur avant d'ouvrir une autre configuration."); return }
        guard confirmLeaving(.open) else { return }
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
        fileURL = asCopy ? nil : url
        originFolder = asCopy ? url.deletingLastPathComponent() : nil
        copyName = asCopy ? url.deletingPathExtension().lastPathComponent + "_copie.conf" : nil
        copyOf = asCopy ? url.lastPathComponent : nil
        if !asCopy { remember(url) }
        resetEditing()
        refreshProblems()
        page = .matrix
    }

    /// A new configuration: here when the window has none, else where the person says.
    func newConfiguration(inputs: Int, outputs: Int) { hub.newConfiguration(inputs: inputs, outputs: outputs, from: self) }

    func create(inputs: Int, outputs: Int) {
        guard !isLocked else { message = String(localized: "Arrêtez le moteur avant de créer une autre configuration."); return }
        guard confirmLeaving(.new) else { return }
        document = ConvDocument(inputs: inputs, outputs: outputs)
        fileURL = nil
        originFolder = nil
        copyName = nil
        copyOf = nil
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
        history.record(label, before: before, scope: page.rawValue)
        document = d
        documentChanged()
    }

    private func documentChanged() {
        if let document { selection.clamp(inputs: document.inputCount, outputs: document.outputCount) }
        refreshProblems()
        syncConnections()
    }

    /// Closes the configuration (not the window): back to the home page, after asking about what is not saved.
    func closeConfiguration() {
        guard isOpen else { return }
        guard !isLocked else { message = String(localized: "Arrêtez le moteur avant de fermer la configuration."); return }
        guard confirmLeaving(.open) else { return }
        document = nil
        fileURL = nil
        originFolder = nil
        copyName = nil
        copyOf = nil
        resetEditing()
        // The state of a start: no configuration, the launch options and the way to look at the responses as they are at first, the home page.
        // The mode (real time, or on sound files) is a choice of the person and stays.
        options = EngineCommand.Options()
        viewMode = .matrix
        liveWiring = nil
        pendingWiring = nil
        refreshProblems()
        page = .home
    }

    private func resetEditing() {
        traces = []
        references = []
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

    /// An undo is for the page where the change was made: the last change, made elsewhere, is not touched from here.
    var canUndo: Bool { !isLocked && history.canUndo(in: page.rawValue) }
    var canRedo: Bool { !isLocked && history.canRedo(in: page.rawValue) }
    var undoLabel: String? { canUndo ? history.undoLabel : nil }
    var redoLabel: String? { canRedo ? history.redoLabel : nil }

    func undo() {
        guard !isLocked, let document, let step = history.undo(current: document, in: page.rawValue) else { return }
        self.document = step.document
        documentChanged()
    }

    /// Undoes the last change when it is the one with this label, from wherever it was made (a change that was made in a view that is only looked at
    /// since cannot have been followed by another one). Returns whether it was undone.
    @discardableResult
    func undoLast(labelled label: String) -> Bool {
        guard !isLocked, let document, history.undoLabel == label, let step = history.undo(current: document) else { return false }
        self.document = step.document
        documentChanged()
        return true
    }

    func redo() {
        guard !isLocked, let document, let step = history.redo(current: document, in: page.rawValue) else { return }
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
            panel.nameFieldStringValue = fileURL?.lastPathComponent ?? copyName ?? defaultFileName
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

    func forgetRecent(_ url: URL) { hub.forgetRecent(url) }
    func clearRecents() { hub.clearRecents() }
    func remember(_ url: URL) { hub.remember(url) }

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
        // Files that are not found: they may be next to the configuration file, in a folder that does not exist here under the old name.
        if problems.contains(where: { if case .fileMissing = $0.kind { true } else { false } }) {
            pathProposals = PathResolver.proposals(for: document, configDirectory: configDirectory, fileExists: { FileManager.default.fileExists(atPath: $0) },
                                                   subfolders: { path in
                var names: [String] = []
                for name in (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? [] {
                    var isDirectory: ObjCBool = false
                    if FileManager.default.fileExists(atPath: (path as NSString).appendingPathComponent(name), isDirectory: &isDirectory), isDirectory.boolValue { names.append(name) }
                }
                return names
            })
        } else {
            pathProposals = []
        }
    }

    /// Puts the files that were found again where they are, in one step of the history.
    func applyPathProposals(_ proposals: [PathProposal]) {
        guard !proposals.isEmpty else { return }
        edit(String(localized: "fichiers retrouvés")) { PathResolver.apply(proposals, to: &$0) }
        loadBin()
    }

    var hasErrors: Bool { problems.contains { $0.severity == .error } }

    // MARK: Running

    /// The command as it is shown: with the file of the person, not the temporary copy that runs when the matrix has been changed.
    var displayedCommand: EngineCommand? {
        guard isOpen else { return nil }
        return makeCommand(configPath: fileURL?.path ?? name)
    }

    private func makeCommand(configPath: String, clientName: String? = nil) -> EngineCommand {
        switch mode {
        case .realTime:
            return EngineCommand(program: .jconvolver, options: options, configPath: configPath, clientName: clientName)
        case .file:
            return EngineCommand(program: .fconvolver, options: options, configPath: configPath,
                                 inputFile: inputFile?.path ?? "", outputFile: outputFile?.path ?? "")
        }
    }

    /// The name to ask JACK for, and the one the client will have when it is known beforehand. The name of the configuration when no client has it; when one
    /// has it, JACK adds a suffix (nothing asked, nothing known: the client is looked up by its process), unless the name is long, which gets a number in
    /// front, asked with `-N` (it prevails over the line of the file).
    func clientNamePlan(base: String) -> (asked: String?, known: String?) {
        var taken = Set(hub.sessions.filter { $0 !== self && $0.controller.isRunning }.compactMap(\.runClientName))
        taken.formUnion(jack.sources.map(\.name))
        taken.formUnion(jack.destinations.map(\.name))
        guard taken.contains(base) else { return (nil, base) }
        guard base.count > 20 else { return (nil, nil) }
        var n = 2
        while taken.contains("\(n) - \(base)") { n += 1 }
        return ("\(n) - \(base)", "\(n) - \(base)")
    }

    /// The program is running: its JACK client is the one it says it has ("client NAME", patch 0005 of jconvolver). JACK cannot say which process a
    /// client belongs to with the library that is installed (`jack_get_client_pid` is not implemented), so for a program that does not say it, it is the
    /// client that appears in the graph after the start, once it is the only new one (or the one that has the name of the file among several).
    /// The connections are made once its ports are all there (their number stops changing); if nothing can tell, nothing is connected.
    func confirmClientName() async {
        let base = document?.content.client ?? "jconvolver"
        var lastCount = -1
        for _ in 0..<80 {
            try? await Task.sleep(for: .milliseconds(100))
            guard controller.isRunning, mode == .realTime else { return }
            jack.refresh()
            let clients = (jack.sources + jack.destinations).filter { !$0.isSystem }
            let name: String
            if let told = controller.clientName {
                // The program said which name JACK gave it (patch 0005 of jconvolver): no guessing.
                if runClientName != told { runClientName = told }
                name = told
            } else {
                // An engine that does not say it (the one of an installation from before the patch): the client that appeared since the start.
                let others = Set(hub.sessions.filter { $0 !== self }.compactMap(\.runClientName))
                var appeared = Set(clients.map(\.name)).subtracting(clientsBeforeStart).subtracting(others)
                if appeared.count > 1 {
                    let named = appeared.filter { $0.hasPrefix(base) || $0.hasSuffix(base) }
                    if named.count == 1 { appeared = named }
                }
                guard appeared.count == 1, let only = appeared.first else { lastCount = -1; continue }
                name = only
            }
            let count = clients.filter { $0.name == name }.reduce(0) { $0 + $1.ports.count }
            if count > 0, count == lastCount { found(name); return }
            lastCount = count
        }
    }

    private func found(_ name: String) {
        runClientName = name
        appliedLinks = []
        syncConnections()
    }

    /// Whether a client of the graph is this session's engine: by its name when it is known, else (just after the start) any client that was not there before.
    func isOwnClient(_ name: String) -> Bool {
        guard controller.isRunning, mode == .realTime else { return false }
        if let runClientName { return name == runClientName }
        return !clientsBeforeStart.contains(name)
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
            // Two engines with the same name: JACK adds a suffix to the second ("jconvolver-01"), and that is the name it keeps. It is looked up by the
            // process once the engine has started (`confirmClientName`), and nothing is connected before. A long name is not left to JACK: the
            // semaphore of a client is named after it and cut at 31 characters on macOS, so a suffix at the end would not tell two apart.
            let base = document?.content.client ?? "jconvolver"
            let plan = mode == .realTime ? clientNamePlan(base: base) : (asked: nil, known: base)
            let command = makeCommand(configPath: path, clientName: plan.asked)
            guard let executable = EngineHelper.executableURL(for: command.program) else {
                message = String(localized: "Le programme \(command.program.rawValue) est introuvable.")
                return
            }
            controller.acknowledgeEnd()
            runCount += 1
            runClientName = plan.known
            clientsBeforeStart = Set((jack.sources + jack.destinations).map(\.name))
            try controller.start(command, executable: executable)
            liveWiring = mode == .realTime ? document : nil
            // The connections are made once the client is found (its ports exist then, and its name is known).
            appliedLinks = []
            if mode == .realTime { Task { await confirmClientName() } }
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
