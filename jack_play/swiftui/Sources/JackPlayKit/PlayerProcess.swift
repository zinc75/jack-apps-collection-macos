// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Where the jack_play program is. The application runs the copy it carries in `Contents/Helpers`: the one that was
/// built and tested with it, whatever is installed elsewhere. Only development builds look further (an environment
/// variable, then the places where an installed jack_play lives), so that they run without the copy.
public enum PlayerHelper {
    public static func executableURL(bundle: Bundle = .main, environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        var candidates = [bundle.bundleURL.appendingPathComponent("Contents/Helpers/jack_play").path]
        #if DEBUG
        if let forced = environment["JACKPLAY_BIN"] { candidates.insert(forced, at: 0) }
        candidates += ["/usr/local/bin/jack_play", "/opt/homebrew/bin/jack_play"]
        #endif
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }
}

/// Runs `jack_play -C` as a child process: reads what it says, sends it commands, and stops it.
///
/// The program reads its standard input for commands and ends when the input is closed, so it cannot outlive the
/// application, even if the application crashes. It starts paused: nothing is played until `send(.play)`.
@MainActor
public final class PlayerProcess {
    public enum LaunchError: Error, Equatable {
        case executableNotFound
        case cannotStart(String)
    }

    /// Everything the program says, and its end, in the order it came.
    public var onEvent: ((PlayerEvent) -> Void)?

    public let command: PlayerCommand
    private let executable: URL
    private let environment: [String: String]?
    private var process: Process?
    private var input: Pipe?
    private var outputParser = PlayerLogParser()
    private var errorParser = PlayerLogParser(isError: true)
    private var stopRequested = false
    private var openOutputs = 0
    private var exitStatus: Int32?
    private var killTimer: DispatchWorkItem?

    public var isRunning: Bool { process?.isRunning ?? false }

    /// The number of the process, which `jack_play` adds to the name of its JACK client.
    public var processIdentifier: Int32? { process?.processIdentifier }

    /// The name of the JACK client of the program, once it runs: its ports are `<clientName>:out_1`, `out_2` …
    /// The program says the name JACK gave it, before "ready". Until then it is the name asked for (the program is
    /// started with `-u`, so it does not add its process number), which JACK may change if another client has it.
    public var clientName: String? {
        guard process != nil else { return nil }
        return reportedName ?? command.settings.safeClientName
    }
    private var reportedName: String?

    /// - Parameter environment: the environment of the program; nil keeps the one of the application. Tests use it to
    ///   point the program to a JACK server of their own.
    public init(executable: URL, command: PlayerCommand, environment: [String: String]? = nil) {
        self.executable = executable
        self.command = command
        self.environment = environment
    }

    public func start() throws {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw LaunchError.executableNotFound }
        let process = Process()
        process.executableURL = executable
        process.arguments = command.arguments
        if let environment { process.environment = environment }
        let input = Pipe(), output = Pipe(), error = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error
        // Writing to a program that has ended must fail, not kill the application with a SIGPIPE.
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        self.process = process
        self.input = input
        openOutputs = 2

        func read(_ pipe: Pipe, error isError: Bool) {
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
                            let events = isError ? self.errorParser.feed(data) : self.outputParser.feed(data)
                            for event in events {
                                if case .client(let name) = event { self.reportedName = name }
                                self.onEvent?(event)
                            }
                        }
                    }
                }
            }
        }
        read(output, error: false)
        read(error, error: true)

        process.terminationHandler = { [weak self] finished in
            let status = finished.terminationStatus
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.exitStatus = status
                    self?.finishIfDone()
                }
            }
        }
        do { try process.run() } catch {
            self.process = nil
            self.input = nil
            throw LaunchError.cannotStart(error.localizedDescription)
        }
    }

    /// Sends a command. Nothing happens if the program has ended.
    public func send(_ control: PlayerControl) {
        guard isRunning, let handle = input?.fileHandleForWriting else { return }
        try? handle.write(contentsOf: Data((control.line + "\n").utf8))
    }

    /// Asks the program to leave, and ends it if it has not done so after `grace` seconds.
    public func stop(grace: TimeInterval = 2) {
        guard let process, process.isRunning, !stopRequested else { return }
        stopRequested = true
        send(.quit)
        let work = DispatchWorkItem { [weak process] in process?.terminate() }
        killTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + grace, execute: work)
    }

    /// Ends the program now (the application is quitting).
    public func terminate() {
        stopRequested = true
        process?.terminate()
    }

    /// The end is reported once the program has ended and what it wrote has been read to the end.
    private func finishIfDone() {
        guard openOutputs <= 0, let status = exitStatus else { return }
        exitStatus = nil
        killTimer?.cancel()
        try? input?.fileHandleForWriting.close()
        input = nil
        process = nil
        onEvent?(.exited(status: status, requested: stopRequested))
    }
}
