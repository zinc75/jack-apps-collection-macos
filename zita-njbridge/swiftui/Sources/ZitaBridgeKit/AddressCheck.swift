// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// What an address typed in a field is.
public enum AddressSyntax: Equatable, Sendable {
    case empty
    case ipv4
    /// With or without its interface after a "%".
    case ipv6
    /// A name of a machine, written as the system accepts them: it is still to be found.
    case hostname
    /// Neither an address nor a name: "10.10.10.999", "10.10.10", "mon adresse", "a..b".
    case invalid
}

public enum AddressCheck {
    public static func syntax(of text: String) -> AddressSyntax {
        let address = text.trimmingCharacters(in: .whitespaces)
        guard !address.isEmpty else { return .empty }
        if address.contains(":") { return isIPv6(address) ? .ipv6 : .invalid }
        // Only digits and dots: it is meant as an IPv4 address, and must be a whole one (no name is made of numbers only).
        if address.allSatisfy({ $0.isNumber || $0 == "." }) { return isIPv4(address) ? .ipv4 : .invalid }
        return isHostname(address) ? .hostname : .invalid
    }

    private static func isIPv4(_ text: String) -> Bool {
        var buffer = in_addr()
        return text.withCString { inet_pton(AF_INET, $0, &buffer) } == 1
    }

    private static func isIPv6(_ text: String) -> Bool {
        let parts = text.split(separator: "%", maxSplits: 1, omittingEmptySubsequences: false)
        if parts.count == 2 {
            // The interface: a name such as en8, en0, bridge0.
            let zone = parts[1]
            guard !zone.isEmpty, zone.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-") }) else { return false }
        }
        var buffer = in6_addr()
        return String(parts[0]).withCString { inet_pton(AF_INET6, $0, &buffer) } == 1
    }

    /// Labels of letters, digits and hyphens (not at the ends) of 63 characters at most, separated by dots, 253 in all; a trailing dot is allowed.
    private static func isHostname(_ text: String) -> Bool {
        var name = text
        if name.hasSuffix(".") { name.removeLast() }
        guard !name.isEmpty, name.count <= 253 else { return false }
        return name.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { label in
            !label.isEmpty && label.count <= 63 && !label.hasPrefix("-") && !label.hasSuffix("-")
                && label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
        }
    }
}
