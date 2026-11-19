// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The command line of one program: what the application runs, and what it shows as "the generated command line".
public struct BridgeCommand: Equatable, Sendable {
    public enum Program: String, Sendable {
        case sender = "zita-j2n"
        case receiver = "zita-n2j"
    }

    public let program: Program
    public let arguments: [String]

    /// - Parameter jackServer: the name of the JACK server (`--jserv`); nil for the default one. Tests use it to reach a server of their own.
    public init(sender s: SendSettings, jackServer: String? = nil) {
        program = .sender
        var a = ["--jname", s.clientName]
        if let jackServer { a += ["--jserv", jackServer] }
        a += ["--chan", "\(s.channels)"]
        switch s.format {
        case .bits16: a.append("--16bit")
        case .bits24: a.append("--24bit")
        case .float32: a.append("--float")
        }
        if s.packetSize != 1500 { a += ["--mtu", "\(s.packetSize)"] }
        if s.multicast, s.hops != 1 { a += ["--hops", "\(s.hops)"] }
        Self.append(ipVersion: s.ipVersion, to: &a)
        a += [s.address, "\(s.port)"]
        if s.multicast { a.append(s.interface) }
        arguments = a
    }

    /// The receiver always runs with `--info`: the application reads the buffer margin from what it prints.
    public init(receiver r: ReceiveSettings, jackServer: String? = nil) {
        program = .receiver
        var a = ["--jname", r.clientName]
        if let jackServer { a += ["--jserv", jackServer] }
        a += ["--chan", ChannelList.format(r.effectiveChannels), "--buff", "\(r.bufferMilliseconds)"]
        if let delay = r.filterDelay { a += ["--filt", "\(delay)"] }
        a.append("--info")
        Self.append(ipVersion: r.ipVersion, to: &a)
        a += [r.address, "\(r.port)"]
        if r.multicast { a.append(r.interface) }
        arguments = a
    }

    private static func append(ipVersion: IPVersion, to a: inout [String]) {
        switch ipVersion {
        case .automatic: break
        case .ipv4: a.append("--ipv4")
        case .ipv6: a.append("--ipv6")
        }
    }

    /// The line as one would type it in a terminal: arguments with a space or a special character are quoted.
    public func display() -> String {
        ([program.rawValue] + arguments.map(Self.quoted)).joined(separator: " ")
    }

    private static func quoted(_ argument: String) -> String {
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.,:/%@=+")
        if !argument.isEmpty, argument.unicodeScalars.allSatisfy({ safe.contains($0) }) { return argument }
        return "'" + argument.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
