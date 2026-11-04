// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation

/// Where the jack_capture program is. The application runs the copy it carries in `Contents/Helpers`: the one that
/// was built and tested with it, whatever is installed elsewhere. Only development builds look further (an
/// environment variable, then the places where an installed jack_capture lives), so that they run without the copy.
public enum CaptureHelper {
    public static func executableURL(bundle: Bundle = .main, environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        var candidates = [bundle.bundleURL.appendingPathComponent("Contents/Helpers/jack_capture").path]
        #if DEBUG
        if let forced = environment["JACKCAPTURE_BIN"] { candidates.insert(forced, at: 0) }
        candidates += ["/usr/local/bin/jack_capture", "/opt/homebrew/bin/jack_capture"]
        #endif
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }
}

/// Runs jack_capture as a child process, reads what it says, and stops it the way Ctrl-C does.
///
/// jack_capture reads its standard input and stops at the first Return, or at the end of the input: the pipe
/// to its input is therefore kept open for as long as it runs. A stop is a SIGINT, which makes it close the
/// file properly. In timemachine mode it waits for a Return to start writing: `sendReturn()`.
@MainActor
public final class CaptureRunner {
    public enum LaunchError: Error, Equatable {
        case executableNotFound
        case cannotStart(String)
    }

    public var onEvent: ((CaptureEvent) -> Void)?
    /// The exit status, and whether the stop was asked for.
    public var onExit: ((Int32, Bool) -> Void)?

    private let executable: URL
    private let arguments: [String]
    private let directory: URL
    private var process: Process?
    private var input: Pipe?
    private let parser = CaptureLogParser()
    private var stopRequested = false
    private var openOutputs = 0
    private var exitStatus: Int32?
    private var killTimer: DispatchWorkItem?

    public var isRunning: Bool { process?.isRunning ?? false }

    public init(executable: URL, arguments: [String], directory: URL) {
        self.executable = executable
        self.arguments = arguments
        self.directory = directory
    }

    public func start() throws {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw LaunchError.executableNotFound }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = directory
        let input = Pipe(), output = Pipe(), error = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error
        self.process = process
        self.input = input
        openOutputs = 2

        func read(_ pipe: Pipe, _ handle: @escaping (String) -> [CaptureEvent]) {
            pipe.fileHandleForReading.readabilityHandler = { [weak self] file in
                let data = file.availableData
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        if data.isEmpty {
                            file.readabilityHandler = nil
                            self.openOutputs -= 1
                            self.finishIfDone()
                        } else {
                            for event in handle(String(decoding: data, as: UTF8.self)) { self.onEvent?(event) }
                        }
                    }
                }
            }
        }
        read(output) { [parser] in parser.feedOutput($0) }
        read(error) { [parser] in parser.feedError($0) }

        process.terminationHandler = { [weak self] finished in
            let status = finished.terminationStatus
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.exitStatus = status
                    self?.finishIfDone()
                }
            }
        }
        do { try process.run() } catch { throw LaunchError.cannotStart(error.localizedDescription) }
    }

    /// Return on its input: starts the writing in timemachine mode.
    public func sendReturn() {
        try? input?.fileHandleForWriting.write(contentsOf: Data([0x0A]))
    }

    /// The equivalent of Ctrl-C. If the program has not finished after 20 s, it is ended.
    public func stop() {
        guard let process, process.isRunning, !stopRequested else { return }
        stopRequested = true
        process.interrupt()
        let work = DispatchWorkItem { [weak process] in process?.terminate() }
        killTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: work)
    }

    /// Ends the program now (the application is quitting).
    public func terminate() {
        stopRequested = true
        process?.terminate()
    }

    /// The exit is reported once the program has ended and its outputs are read to the end.
    private func finishIfDone() {
        guard openOutputs <= 0, let status = exitStatus else { return }
        exitStatus = nil
        killTimer?.cancel()
        try? input?.fileHandleForWriting.close()
        input = nil
        process = nil
        onExit?(status, stopRequested)
    }
}
