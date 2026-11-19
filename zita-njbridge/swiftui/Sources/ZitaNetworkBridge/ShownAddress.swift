// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// How an address and a port are written on the link page. A port is never grouped by digits ("9999", not "9 999").
///
/// In a debug build, ZITABRIDGE_FAKE_ADDRS=<this Mac>,<the other Mac> shows those two addresses in place of the loopback one of
/// the demo link (and port 9999 for 19999), so that screenshots read like a real network. Nothing is changed in the link itself.
enum ShownAddress {
    #if DEBUG
    private static let fake: (this: String, other: String)? = {
        guard let list = ProcessInfo.processInfo.environment["ZITABRIDGE_FAKE_ADDRS"]?.split(separator: ",").map(String.init), list.count == 2 else { return nil }
        return (list[0], list[1])
        }()
    #endif

    /// The address on which this Mac listens.
    static func listening(_ address: String) -> String {
        #if DEBUG
        if let fake, address == "127.0.0.1" { return fake.this }
        #endif
        return address
    }

    /// The address of the other Mac.
    static func other(_ address: String) -> String {
        #if DEBUG
        if let fake, address == "127.0.0.1" { return fake.other }
        #endif
        return address
    }

    static func port(_ port: Int) -> String {
        #if DEBUG
        if fake != nil, port == 19999 { return "9999" }
        #endif
        return String(port)
    }
}
