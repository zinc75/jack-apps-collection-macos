// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import ZitaBridgeKit

final class NetworkTests: XCTestCase {
    // MARK: Addresses

    func testAddressesAreSortedIntoKinds() {
        let v4: [(String, AddressKind)] = [
            ("127.0.0.1", .loopback), ("169.254.81.9", .linkLocal), ("10.10.10.1", .privateNetwork), ("192.168.1.20", .privateNetwork),
            ("172.16.0.5", .privateNetwork), ("172.31.255.1", .privateNetwork), ("172.32.0.1", .global), ("163.173.140.160", .global),
        ]
        for (text, kind) in v4 { XCTAssertEqual(NetworkInventory.classify(text, family: .ipv4), kind, text) }
        let v6: [(String, AddressKind)] = [
            ("::1", .loopback), ("fe80::1c3:a2ff:fe10:5%en7", .linkLocal), ("fd12:3456::1", .privateNetwork), ("2001:db8::1", .global),
        ]
        for (text, kind) in v6 { XCTAssertEqual(NetworkInventory.classify(text, family: .ipv6), kind, text) }
    }

    func testThisMacHasItsLoopbackAndEveryAddressIsWellFormed() throws {
        let interfaces = NetworkInventory.interfaces()
        let loopback = try XCTUnwrap(interfaces.first { $0.isLoopback }, "no loopback interface")
        XCTAssertTrue(loopback.addresses.contains { $0.address == "127.0.0.1" && $0.kind == .loopback })
        XCTAssertEqual(interfaces.last?.isLoopback, true, "the real interfaces come first")
        for interface in interfaces {
            XCTAssertFalse(interface.name.isEmpty); XCTAssertFalse(interface.displayName.isEmpty)
            XCTAssertFalse(interface.addresses.isEmpty, "an interface without address is not listed")
            for a in interface.addresses {
                XCTAssertEqual(a.interface, interface.name)
                XCTAssertFalse(a.address.isEmpty)
                if a.kind == .linkLocal, a.family == .ipv6 { XCTAssertTrue(a.address.contains("%"), "a link-local IPv6 address needs its interface: \(a.address)") }
            }
        }
        XCTAssertEqual(Set(interfaces.map(\.name)).count, interfaces.count, "an interface is listed once")
    }

    func testTheUsableAddressesComeBeforeTheLinkLocalOnes() {
        for interface in NetworkInventory.interfaces() {
            let ranks = interface.addresses.map { a -> Int in a.kind == .loopback ? 2 : a.kind == .linkLocal ? 1 : 0 }
            XCTAssertEqual(ranks, ranks.sorted(), interface.name)
        }
    }

    func testTheCablesComeBeforeWiFiAndTheLoopbackIsLast() {
        func interface(_ name: String, _ kind: InterfaceKind, loopback: Bool = false) -> NetworkInterface {
            NetworkInterface(name: name, displayName: name, isLoopback: loopback, supportsMulticast: true,
                             addresses: [NetworkAddress(address: "10.0.0.\(name.count)", interface: name, family: .ipv4, kind: .privateNetwork, interfaceKind: kind)], kind: kind)
        }
        let shuffled = [interface("lo0", .other, loopback: true), interface("en0", .wifi), interface("en10", .ethernet), interface("bridge0", .bridge),
                        interface("en2", .ethernet), interface("utun1", .other)]
        XCTAssertEqual(NetworkInventory.ordered(shuffled).map(\.name), ["en2", "en10", "bridge0", "utun1", "en0", "lo0"])
        XCTAssertTrue(InterfaceKind.wifi.isWireless); XCTAssertFalse(InterfaceKind.ethernet.isWireless)
    }

    func testTheSystemTypesAreRecognised() {
        XCTAssertEqual(NetworkInventory.kind(of: "Ethernet"), .ethernet)
        XCTAssertEqual(NetworkInventory.kind(of: "IEEE80211"), .wifi)
        XCTAssertEqual(NetworkInventory.kind(of: "Bridge"), .bridge)
        XCTAssertEqual(NetworkInventory.kind(of: "Bluetooth"), .other)
        XCTAssertEqual(NetworkInventory.kind(of: nil), .other)
    }

    func testTheRealInterfacesKnowTheirType() throws {
        let known = NetworkInventory.systemInterfaces()
        XCTAssertFalse(known.isEmpty, "System Settings lists no interface")
        for interface in NetworkInventory.interfaces() where interface.isInSystemSettings {
            XCTAssertEqual(interface.kind, known[interface.name]?.kind, interface.name)
            XCTAssertTrue(interface.addresses.allSatisfy { $0.interfaceKind == interface.kind })
        }
        let order = NetworkInventory.interfaces().filter { !$0.isLoopback }.map(\.kind)
        XCTAssertEqual(order, order.sorted { rankOf($0) < rankOf($1) }, "cables, then others, then Wi-Fi")
    }

    private func rankOf(_ k: InterfaceKind) -> Int { k == .ethernet ? 0 : k == .bridge ? 1 : k == .other ? 2 : 3 }

    func testOnlyTheNetworksOfSystemSettingsAreOffered() {
        func address(_ text: String, _ interface: String, _ family: AddressFamily, _ kind: AddressKind) -> NetworkAddress {
            NetworkAddress(address: text, interface: interface, family: family, kind: kind)
        }
        let interfaces = [
            NetworkInterface(name: "en7", displayName: "USB 10/100/1000 LAN", isLoopback: false, supportsMulticast: true,
                             addresses: [address("10.10.10.1", "en7", .ipv4, .privateNetwork), address("fe80::1%en7", "en7", .ipv6, .linkLocal)]),
            NetworkInterface(name: "en0", displayName: "Wi-Fi", isLoopback: false, supportsMulticast: true,
                             addresses: [address("fe80::2%en0", "en0", .ipv6, .linkLocal), address("192.168.1.20", "en0", .ipv4, .privateNetwork)]),
            NetworkInterface(name: "utun3", displayName: "utun3", isLoopback: false, supportsMulticast: true, addresses: [address("fe80::3%utun3", "utun3", .ipv6, .linkLocal)]),
            NetworkInterface(name: "lo0", displayName: "lo0", isLoopback: true, supportsMulticast: true, addresses: [address("127.0.0.1", "lo0", .ipv4, .loopback)]),
        ]
        XCTAssertEqual(NetworkInventory.listenChoices(from: interfaces).map(\.address), ["10.10.10.1", "192.168.1.20", "fe80::1%en7", "fe80::2%en0"])
        XCTAssertEqual(NetworkInventory.multicastChoices(from: interfaces).map(\.name), ["en7", "en0"])
        XCTAssertTrue(interfaces[0].isInSystemSettings); XCTAssertFalse(interfaces[2].isInSystemSettings)
    }

    // MARK: Ping output (captured from the real programs)

    func testAPingThatAnswers() {
        let output = """
        PING 127.0.0.1 (127.0.0.1): 56 data bytes
        64 bytes from 127.0.0.1: icmp_seq=0 ttl=64 time=0.061 ms

        --- 127.0.0.1 ping statistics ---
        3 packets transmitted, 3 packets received, 0.0% packet loss
        round-trip min/avg/max/stddev = 0.061/0.106/0.133/0.032 ms
        """
        XCTAssertEqual(PingParser.parse(output: output, status: 0),
                       .replied(PingReply(sent: 3, received: 3, lossPercent: 0, minimum: 0.061, average: 0.106, maximum: 0.133)))
    }

    func testAPingOfIPv6HasANanStandardDeviation() {
        let output = """
        --- ::1 ping6 statistics ---
        2 packets transmitted, 2 packets received, 0.0% packet loss
        round-trip min/avg/max/std-dev = 0.096/0.096/0.096/nan ms
        """
        XCTAssertEqual(PingParser.parse(output: output, status: 0),
                       .replied(PingReply(sent: 2, received: 2, lossPercent: 0, minimum: 0.096, average: 0.096, maximum: 0.096)))
    }

    func testSomePacketsLost() {
        let output = """
        --- 10.10.10.2 ping statistics ---
        3 packets transmitted, 2 packets received, 33.3% packet loss
        round-trip min/avg/max/stddev = 1.1/1.4/1.7/0.3 ms
        """
        guard case .replied(let r) = PingParser.parse(output: output, status: 0) else { return XCTFail() }
        XCTAssertEqual(r.received, 2); XCTAssertEqual(r.lossPercent, 33.3, accuracy: 1e-9)
    }

    func testNoAnswer() {
        let output = """
        PING 192.0.2.1 (192.0.2.1): 56 data bytes
        Request timeout for icmp_seq 0

        --- 192.0.2.1 ping statistics ---
        2 packets transmitted, 0 packets received, 100.0% packet loss
        """
        XCTAssertEqual(PingParser.parse(output: output, status: 2), .noAnswer(sent: 2))
    }

    func testAnUnknownHost() {
        XCTAssertEqual(PingParser.parse(output: "ping: cannot resolve no.such.host.invalid: Unknown host\n", status: 68), .unknownHost)
        XCTAssertEqual(PingParser.parse(output: "ping6: nodename nor servname provided, or not known\n", status: 68), .unknownHost)
    }

    func testNoWayToTheMachine() {
        XCTAssertEqual(PingParser.parse(output: "PING 10.9.9.9 (10.9.9.9): 56 data bytes\nping: sendto: No route to host\n", status: 68), .unreachable("No route to host"))
        let output = "--- 10.9.9.9 ping statistics ---\n2 packets transmitted, 0 packets received, 100.0% packet loss\nping: sendto: Host is down\n"
        XCTAssertEqual(PingParser.parse(output: output, status: 2), .unreachable("Host is down"))
    }

    func testAnythingElseIsAFailureWithItsText() {
        XCTAssertEqual(PingParser.parse(output: "ping: something odd\n", status: 64), .failed("ping: something odd"))
        XCTAssertEqual(PingParser.parse(output: "", status: 64), .failed("ping ended with status 64"))
    }

    // MARK: The real thing

    func testPingingThisMac() async {
        guard case .replied(let r) = await Pinger.ping(host: "127.0.0.1", count: 2) else { return XCTFail("127.0.0.1 does not answer") }
        XCTAssertEqual(r.sent, 2); XCTAssertEqual(r.received, 2); XCTAssertEqual(r.lossPercent, 0)
        XCTAssertNotNil(r.average)
        guard case .replied = await Pinger.ping(host: "::1", count: 2) else { return XCTFail("::1 does not answer") }
    }

    func testAnUnknownNameIsRecognised() async {
        let outcome = await Pinger.ping(host: "no.such.host.invalid", count: 1)
        XCTAssertEqual(outcome, .unknownHost)
    }

    func testWhatLooksLikeAnOptionIsNeverGivenToPing() async {
        guard case .failed = await Pinger.ping(host: "-f") else { return XCTFail("an option went through") }
        guard case .failed = await Pinger.ping(host: "  ") else { return XCTFail("an empty address went through") }
    }
}
