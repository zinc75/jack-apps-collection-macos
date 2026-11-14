// SPDX-License-Identifier: MIT

import Foundation
import Darwin

/// The JackMoebius daemon, asked which application stands behind each client. JackMoebius makes a JACK client for the
/// CoreAudio applications it exposes; the daemon knows their bundle identifiers (`key`) and the names of their clients
/// (`name`). It listens on a Unix socket: one JSON line in ("{"command":"apps"}"), one JSON line out, then it closes.
/// Read only; nothing happens when the daemon is not there. Shared by the applications of the collection that show the clients of a
/// JACK server (Jack Capture, Klick).
public enum JackMoebiusDaemon {
    public nonisolated static var socketPath: String {
        #if DEBUG
        // Development aid: a socket of a fake daemon (JACKAPPS_MOEBIUS_SOCKET; JACKCAPTURE_MOEBIUS_SOCKET as before).
        let environment = ProcessInfo.processInfo.environment
        if let forced = environment["JACKAPPS_MOEBIUS_SOCKET"] ?? environment["JACKCAPTURE_MOEBIUS_SOCKET"] { return forced }
        #endif
        return "/tmp/jackmoebius.sock"
    }

    public nonisolated static var isPresent: Bool { FileManager.default.fileExists(atPath: socketPath) }

    /// The bundle identifier of each application the daemon knows, by the name of its JACK client.
    /// Blocking (at most 2 s): call it away from the main actor.
    public nonisolated static func applicationKeys() -> [String: String] {
        guard let reply = request(command: "apps") else { return [:] }
        return parseApps(reply)
    }

    /// Reads the data of an `apps` reply: a list of rows with `key` and `name` (other fields are ignored: the
    /// daemon may add some). Applications without a resolvable bundle (`path:…`) have no icon to give.
    public nonisolated static func parseApps(_ data: Any?) -> [String: String] {
        guard let rows = data as? [[String: Any]] else { return [:] }
        var keys: [String: String] = [:]
        for row in rows {
            guard let key = row["key"] as? String, let name = row["name"] as? String, !key.isEmpty, !key.hasPrefix("path:") else { continue }
            keys[name] = key
        }
        return keys
    }

    /// The key for a client name: the exact name, else the same name in another case ("REAPER" for "Reaper").
    public nonisolated static func key(forClient name: String, in keys: [String: String]) -> String? {
        if let exact = keys[name] { return exact }
        let lower = name.lowercased()
        return keys.first { $0.key.lowercased() == lower }?.value
    }

    /// One request, one reply: the `data` of a reply whose status is "ok".
    public nonisolated static func request(command: String) -> Any? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let path = socketPath
        guard path.utf8.count < 104 else { return nil }
        path.withCString { source in
            withUnsafeMutablePointer(to: &address.sun_path) { destination in
                destination.withMemoryRebound(to: CChar.self, capacity: 104) { _ = strlcpy($0, source, 104) }
            }
        }
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else { return nil }

        guard var line = try? JSONSerialization.data(withJSONObject: ["command": command]) else { return nil }
        line.append(0x0A)
        guard line.withUnsafeBytes({ write(fd, $0.baseAddress, $0.count) }) > 0 else { return nil }

        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = read(fd, &chunk, chunk.count)
            if n <= 0 { break }
            buffer.append(contentsOf: chunk[0..<n])
        }
        guard let reply = (try? JSONSerialization.jsonObject(with: buffer)) as? [String: Any], reply["status"] as? String == "ok" else { return nil }
        return reply["data"]
    }
}
