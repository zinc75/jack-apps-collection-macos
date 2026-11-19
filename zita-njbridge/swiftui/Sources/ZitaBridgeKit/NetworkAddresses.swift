// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SystemConfiguration
import Darwin

public enum AddressFamily: Equatable, Sendable { case ipv4, ipv6 }

/// What kind of address it is: it tells whether the other Mac can use it.
public enum AddressKind: Equatable, Sendable {
    /// This Mac itself (127.0.0.1, ::1).
    case loopback
    /// Made by the Mac on a cable with no address server (169.254.x.x, fe80::): good for two Macs linked directly.
    case linkLocal
    /// A private network (10.x, 172.16 to 31.x, 192.168.x, fc00::/7).
    case privateNetwork
    /// Any other unicast address.
    case global
}

/// What a network is made of, as System Settings sees it. A cable is the good choice for audio; Wi-Fi works with a larger buffer.
public enum InterfaceKind: Equatable, Sendable {
    case ethernet
    /// Thunderbolt Bridge, and other bridges between Macs.
    case bridge
    case wifi
    case other

    public var isWireless: Bool { self == .wifi }
}

/// An address of this Mac, on one interface.
public struct NetworkAddress: Equatable, Sendable, Identifiable {
    /// The text of the address. A link-local IPv6 address carries its interface ("fe80::1%en7"), as the programs need it.
    public var address: String
    /// The name of the interface ("en7").
    public var interface: String
    public var family: AddressFamily
    public var kind: AddressKind
    /// What the interface of this address is made of.
    public var interfaceKind = InterfaceKind.other
    public var id: String { address }
}

/// A network interface of this Mac that is up.
public struct NetworkInterface: Equatable, Sendable, Identifiable {
    /// The BSD name ("en7"): the one the programs take for multicast.
    public var name: String
    /// The name the system gives it in its settings ("USB 10/100/1000 LAN", "Wi-Fi"); the BSD name when it has none.
    public var displayName: String
    public var isLoopback: Bool
    public var supportsMulticast: Bool
    public var addresses: [NetworkAddress]
    public var kind = InterfaceKind.other
    public var id: String { name }
    /// A network the person set up in System Settings (a cable, Wi-Fi): the system has a name for it. Tunnels and the
    /// system's own interfaces ("utun3", "llw0") have none.
    public var isInSystemSettings: Bool { displayName != name }
}

public enum NetworkInventory {
    /// The interfaces that are up and have an address, the real ones first, and each with its addresses, the usable first.
    public static func interfaces() -> [NetworkInterface] {
        let system = systemInterfaces()
        var byName = [String: NetworkInterface]()
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            let flags = Int32(entry.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_RUNNING != 0, let sockaddr = entry.pointee.ifa_addr else { continue }
            let family: AddressFamily
            switch Int32(sockaddr.pointee.sa_family) {
            case AF_INET: family = .ipv4
            case AF_INET6: family = .ipv6
            default: continue
            }
            let name = String(cString: entry.pointee.ifa_name)
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(sockaddr, socklen_t(sockaddr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            var text = String(cString: host)
            let kind = classify(text, family: family)
            // The zone is how a link-local address says which interface it is on; add it when the system did not.
            if family == .ipv6, kind == .linkLocal, !text.contains("%") { text += "%" + name }
            let known = system[name]
            var interface = byName[name] ?? NetworkInterface(name: name, displayName: known?.name ?? name, isLoopback: flags & IFF_LOOPBACK != 0,
                                                              supportsMulticast: flags & IFF_MULTICAST != 0, addresses: [], kind: known?.kind ?? .other)
            interface.addresses.append(NetworkAddress(address: text, interface: name, family: family, kind: kind, interfaceKind: interface.kind))
            byName[name] = interface
        }
        return ordered(Array(byName.values))
    }

    /// The cables first, then the others, then Wi-Fi, and the loopback last; the usable addresses of each before the link-local ones.
    static func ordered(_ interfaces: [NetworkInterface]) -> [NetworkInterface] {
        interfaces.map { interface in
            var i = interface
            i.addresses.sort { rank($0.kind) != rank($1.kind) ? rank($0.kind) < rank($1.kind) : ($0.family == .ipv4 && $1.family == .ipv6) }
            return i
        }.sorted { a, b in
            let ra = rank(a), rb = rank(b)
            if ra != rb { return ra < rb }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    private static func rank(_ interface: NetworkInterface) -> Int {
        if interface.isLoopback { return 9 }
        switch interface.kind {
        case .ethernet: return 0
        case .bridge: return 1
        case .other: return 2
        case .wifi: return 3
        }
    }

    private static func rank(_ kind: AddressKind) -> Int {
        switch kind {
        case .privateNetwork, .global: 0
        case .linkLocal: 1
        case .loopback: 2
        }
    }

    /// The addresses worth offering to listen on: those of the networks of System Settings, the IPv4 ones first. The loopback
    /// stays out of the menu; a person who wants it types it.
    public static func listenChoices(from interfaces: [NetworkInterface] = NetworkInventory.interfaces()) -> [NetworkAddress] {
        let all = interfaces.filter { !$0.isLoopback && $0.isInSystemSettings }.flatMap(\.addresses)
        return all.filter { $0.family == .ipv4 } + all.filter { $0.family == .ipv6 }
    }

    /// The interfaces a multicast link can use.
    public static func multicastChoices(from interfaces: [NetworkInterface] = NetworkInventory.interfaces()) -> [NetworkInterface] {
        interfaces.filter { !$0.isLoopback && $0.isInSystemSettings && $0.supportsMulticast }
    }

    /// What System Settings knows of its interfaces, by BSD name: the name it shows, and what the interface is made of.
    static func systemInterfaces() -> [String: (name: String, kind: InterfaceKind)] {
        var result = [String: (name: String, kind: InterfaceKind)]()
        for interface in (SCNetworkInterfaceCopyAll() as? [SCNetworkInterface]) ?? [] {
            guard let bsd = SCNetworkInterfaceGetBSDName(interface) as String?,
                  let name = SCNetworkInterfaceGetLocalizedDisplayName(interface) as String? else { continue }
            result[bsd] = (name, kind(of: SCNetworkInterfaceGetInterfaceType(interface) as String?))
        }
        return result
    }

    static func kind(of systemType: String?) -> InterfaceKind {
        guard let systemType else { return .other }
        if systemType == kSCNetworkInterfaceTypeEthernet as String { return .ethernet }
        if systemType == kSCNetworkInterfaceTypeIEEE80211 as String { return .wifi }
        if systemType == "Bridge" { return .bridge }   // the constant is not public
        return .other
    }

    /// The kind of an address written as text. A zone ("%en7") is ignored.
    static func classify(_ text: String, family: AddressFamily) -> AddressKind {
        let address = String(text.split(separator: "%", maxSplits: 1).first ?? "")
        switch family {
        case .ipv4:
            let p = address.split(separator: ".").compactMap { Int($0) }
            guard p.count == 4 else { return .global }
            if p[0] == 127 { return .loopback }
            if p[0] == 169, p[1] == 254 { return .linkLocal }
            if p[0] == 10 || (p[0] == 172 && (16...31).contains(p[1])) || (p[0] == 192 && p[1] == 168) { return .privateNetwork }
            return .global
        case .ipv6:
            let lower = address.lowercased()
            if lower == "::1" { return .loopback }
            if lower.hasPrefix("fe8") || lower.hasPrefix("fe9") || lower.hasPrefix("fea") || lower.hasPrefix("feb") { return .linkLocal }
            if lower.hasPrefix("fc") || lower.hasPrefix("fd") { return .privateNetwork }
            return .global
        }
    }
}
