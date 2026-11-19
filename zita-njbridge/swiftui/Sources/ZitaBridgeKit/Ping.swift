// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// What a ping learnt: the other machine answers, or why it does not.
public struct PingReply: Equatable, Sendable {
    public var sent: Int
    public var received: Int
    public var lossPercent: Double
    /// Round-trip times in milliseconds.
    public var minimum: Double?
    public var average: Double?
    public var maximum: Double?
}

public enum PingOutcome: Equatable, Sendable {
    /// At least one packet came back.
    case replied(PingReply)
    /// The packets left and none came back: the machine is off, or filters pings.
    case noAnswer(sent: Int)
    /// The name does not resolve.
    case unknownHost
    /// There is no way to that machine ("No route to host", "Host is down").
    case unreachable(String)
    /// The ping could not be run, or the address was refused.
    case failed(String)
}

/// Reads what `/sbin/ping` and `/sbin/ping6` print.
public enum PingParser {
    public static func parse(output: String, status: Int32) -> PingOutcome {
        if output.contains("Unknown host") || output.contains("nodename nor servname") || output.contains("cannot resolve") {
            return .unknownHost
        }
        var sent = 0, received = 0, loss = 0.0, haveSummary = false
        var times: (Double, Double, Double)?
        for raw in output.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            // "3 packets transmitted, 3 packets received, 0.0% packet loss"
            if line.contains("packets transmitted") {
                let numbers = line.split(whereSeparator: { !($0.isNumber || $0 == ".") }).compactMap { Double($0) }
                if numbers.count >= 3 { sent = Int(numbers[0]); received = Int(numbers[1]); loss = numbers[2]; haveSummary = true }
            }
            // "round-trip min/avg/max/stddev = 0.061/0.106/0.133/0.032 ms"
            if line.hasPrefix("round-trip"), let equals = line.firstIndex(of: "=") {
                let values = line[line.index(after: equals)...].split(whereSeparator: { $0 == "/" || $0 == " " }).compactMap { Double($0) }
                if values.count >= 3 { times = (values[0], values[1], values[2]) }
            }
        }
        if haveSummary {
            if received == 0 {
                if let reason = unreachableReason(output) { return .unreachable(reason) }
                return .noAnswer(sent: sent)
            }
            return .replied(PingReply(sent: sent, received: received, lossPercent: loss, minimum: times?.0, average: times?.1, maximum: times?.2))
        }
        if let reason = unreachableReason(output) { return .unreachable(reason) }
        let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return .failed(text.isEmpty ? "ping ended with status \(status)" : text)
    }

    private static func unreachableReason(_ output: String) -> String? {
        for reason in ["No route to host", "Host is down", "Network is unreachable", "Network is down"] where output.contains(reason) { return reason }
        return nil
    }
}

public enum Pinger {
    /// Pings `host` a few times. Runs `ping6` for an IPv6 address (or when IPv6 is asked for), `ping` otherwise.
    public static func ping(host: String, count: Int = 3, ipVersion: IPVersion = .automatic) async -> PingOutcome {
        let name = host.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return .failed("No address") }
        // Not an option for the program, whatever was typed.
        guard !name.hasPrefix("-") else { return .failed("Not an address: \(name)") }
        let useIPv6 = name.contains(":") || ipVersion == .ipv6
        let program = useIPv6 ? "/sbin/ping6" : "/sbin/ping"
        guard FileManager.default.isExecutableFile(atPath: program) else { return .failed("\(program) is not available") }
        // ping waits for a second at most for each packet (-W is in milliseconds for ping; ping6 has no such option).
        var arguments = ["-c", "\(max(1, min(count, 10)))"]
        if useIPv6 { arguments += ["-i", "0.3"] } else { arguments += ["-W", "1000", "-i", "0.3"] }
        arguments += [name]
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: run(program, arguments, limit: Double(count) * 1.5 + 3))
            }
        }
    }

    private static func run(_ program: String, _ arguments: [String], limit: TimeInterval) -> PingOutcome {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: program)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return .failed("\(error)") }
        // A ping that never ends is stopped: it prints its summary when it receives SIGINT.
        DispatchQueue.global().asyncAfter(deadline: .now() + limit) { if process.isRunning { process.interrupt() } }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return PingParser.parse(output: String(decoding: data, as: UTF8.self), status: process.terminationStatus)
    }
}
