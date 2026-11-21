// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import CJConvolverPty

/// How a run of a program ended.
public struct EngineTermination: Equatable, Sendable {
    public enum Outcome: Equatable, Sendable {
        /// The program did its work and ended (fconvolver, with the exit code 0).
        case finished
        /// It was asked to end, with SIGINT, and did.
        case stoppedOnRequest
        /// jconvolver ended on its own, and said why. Its exit code is 0 all the same.
        case stoppedByEngine(EngineMessage.StopReason)
        /// It ended with an error: the exit code, which is 128 plus the number of the signal when it was killed by one.
        case failed(status: Int32)
    }

    public var status: Int32
    public var outcome: Outcome

    /// What an end means. The exit code alone does not tell: jconvolver returns 0 after "CPU overload, exiting.".
    static func outcome(status: Int32, requested: Bool, stopReason: EngineMessage.StopReason?) -> Outcome {
        if requested { return .stoppedOnRequest }
        if let stopReason { return .stoppedByEngine(stopReason) }
        return status == 0 ? .finished : .failed(status: status)
    }
}

/// What a running program gives, in the order it comes.
public enum EngineEvent: Equatable, Sendable {
    case message(EngineMessage)
    case ended(EngineTermination)
}

/// The running side of a program: its pseudo-terminal, the reading of what it says, and its end. Everything happens on one
/// queue; the events go to the main queue.
final class EnginePtySession: @unchecked Sendable {
    private let queue = DispatchQueue(label: "jconvolver.engine.pty")
    private var parser = EngineLogParser()
    private var master: Int32 = -1
    private var pid: pid_t = -1
    private var readSource: DispatchSourceRead?
    private var exitSource: DispatchSourceProcess?
    private var stopRequested = false
    private var finished = false
    private var stopReason: EngineMessage.StopReason?
    private let lock = NSLock()
    private var pidValue: pid_t = -1

    /// The process identifier, readable from any thread.
    var processIdentifier: pid_t { lock.lock(); defer { lock.unlock() }; return pidValue }

    func start(path: String, arguments: [String], environment: [String: String], deliver: @escaping @Sendable ([EngineEvent]) -> Void) throws {
        var argv = ([path] + arguments).map { strdup($0) } + [nil]
        var envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { argv.forEach { free($0) }; envp.forEach { free($0) } }
        var fd: Int32 = -1
        let child = jconv_spawn_pty(path, &argv, &envp, &fd)
        guard child > 0 else { throw EngineProcess.LaunchError.cannotStart(String(cString: strerror(errno))) }
        master = fd
        pid = child
        lock.lock(); pidValue = child; lock.unlock()
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)

        let reader = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        reader.setEventHandler { [weak self] in self?.readAvailable(deliver) }
        readSource = reader
        reader.resume()

        let watcher = DispatchSource.makeProcessSource(identifier: child, eventMask: .exit, queue: queue)
        watcher.setEventHandler { [weak self] in self?.childExited(deliver) }
        exitSource = watcher
        watcher.resume()
    }

    private func take(_ messages: [EngineMessage]) -> [EngineEvent] {
        for message in messages { if let reason = message.stopReason { stopReason = reason } }
        return messages.map { .message($0) }
    }

    private func readAvailable(_ deliver: @escaping @Sendable ([EngineEvent]) -> Void) {
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = read(master, &buffer, buffer.count)
            if n > 0 {
                let events = take(parser.feed(Data(buffer[0..<n])))
                if !events.isEmpty { DispatchQueue.main.async { deliver(events) } }
            } else {
                break   // 0 or EIO: the program closed its side; EAGAIN: nothing more for now.
            }
        }
    }

    private func childExited(_ deliver: @escaping @Sendable ([EngineEvent]) -> Void) {
        guard !finished else { return }
        finished = true
        readAvailable(deliver)   // the last lines, written just before the end
        let last = take(parser.finish())
        if !last.isEmpty { DispatchQueue.main.async { deliver(last) } }
        var status: Int32 = 0
        waitpid(pid, &status, 0)
        let signal = status & 0x7f
        let code: Int32 = signal == 0 ? (status >> 8) & 0xff : 128 + signal
        let termination = EngineTermination(status: code, outcome: EngineTermination.outcome(status: code, requested: stopRequested, stopReason: stopReason))
        readSource?.cancel(); exitSource?.cancel()
        readSource = nil; exitSource = nil
        close(master); master = -1
        DispatchQueue.main.async { deliver([.ended(termination)]) }
    }

    /// Asks the program to end (SIGINT: a plain kill ends jconvolver in the middle of a cycle of JACK, which makes an xrun
    /// for every client of the server); if it is still there after two seconds, kills it.
    func stop() {
        queue.async { [self] in
            guard !finished, pid > 0 else { return }
            stopRequested = true
            kill(pid, SIGINT)
            let target = pid
            queue.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self, !self.finished else { return }
                kill(target, SIGKILL)
            }
        }
    }

    /// Lets go of the pseudo-terminal: the kernel then sends SIGHUP to the program, which ends. This is what happens too when
    /// the application crashes.
    func hangUp() {
        queue.sync {
            guard !finished else { return }
            readSource?.cancel(); exitSource?.cancel()
            readSource = nil; exitSource = nil
            if master >= 0 { close(master); master = -1 }
            finished = true
            // The program is reaped once it has ended (a program that ignored the hang-up is killed after two seconds): a
            // process that is not waited for stays as a zombie.
            let target = pid
            if target > 0 {
                DispatchQueue.global(qos: .utility).async {
                    var status: Int32 = 0
                    for _ in 0..<40 {
                        if waitpid(target, &status, WNOHANG) != 0 { return }
                        usleep(50_000)
                    }
                    kill(target, SIGKILL)
                    waitpid(target, &status, 0)
                }
            }
        }
    }
}

/// Runs jconvolver or fconvolver in a pseudo-terminal, reads what it says and ends it.
///
/// The programs do not read their input, so they are stopped with a signal. They cannot outlive the application: when the
/// pseudo-terminal is closed, the program gets SIGHUP.
@MainActor
public final class EngineProcess {
    public enum LaunchError: Error, Equatable {
        case executableNotFound
        case cannotStart(String)
    }

    /// Everything the program says, and its end, in the order it came.
    public var onEvent: ((EngineEvent) -> Void)?

    public let command: EngineCommand
    private let executable: URL
    private let environment: [String: String]
    private let session = EnginePtySession()
    private var started = false
    private var ended = false

    /// - Parameter environment: the environment of the program; nil keeps the one of the application.
    public init(executable: URL, command: EngineCommand, environment: [String: String]? = nil) {
        self.executable = executable
        self.command = command
        self.environment = environment ?? ProcessInfo.processInfo.environment
    }

    deinit { session.hangUp() }

    public var isRunning: Bool { started && !ended }
    public var processIdentifier: Int32? { started ? session.processIdentifier : nil }

    public func start() throws {
        guard !started else { return }
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw LaunchError.executableNotFound }
        try session.start(path: executable.path, arguments: command.arguments, environment: environment) { [weak self] events in
            MainActor.assumeIsolated {
                guard let self else { return }
                for event in events {
                    if case .ended = event { self.ended = true }
                    self.onEvent?(event)
                }
            }
        }
        started = true
    }

    /// Asks the program to end; `onEvent` says `.ended` with `.stoppedOnRequest` when it has.
    public func stop() { if isRunning { session.stop() } }
}
