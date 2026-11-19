// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import ZitaBridgeKit

final class BridgeCommandTests: XCTestCase {
    private func sender(_ edit: (inout SendSettings) -> Void = { _ in }) -> SendSettings {
        var s = SendSettings(); s.address = "10.10.10.1"; edit(&s); return s
    }
    private func receiver(_ edit: (inout ReceiveSettings) -> Void = { _ in }) -> ReceiveSettings {
        var r = ReceiveSettings(); r.address = "10.10.10.1"; edit(&r); return r
    }

    // MARK: Command lines

    func testTheDefaultSenderCommand() {
        let c = BridgeCommand(sender: sender())
        XCTAssertEqual(c.program, .sender)
        XCTAssertEqual(c.arguments, ["--jname", "zita-j2n", "--chan", "2", "--24bit", "10.10.10.1", "9999"])
        XCTAssertEqual(c.display(), "zita-j2n --jname zita-j2n --chan 2 --24bit 10.10.10.1 9999")
    }

    func testTheDefaultReceiverCommandAsksForTheInformationLines() {
        let c = BridgeCommand(receiver: receiver())
        XCTAssertEqual(c.program, .receiver)
        XCTAssertEqual(c.arguments, ["--jname", "zita-n2j", "--chan", "1,2", "--buff", "10", "--info", "10.10.10.1", "9999"])
    }

    func testTheSenderOptions() {
        let c = BridgeCommand(sender: sender { $0.channels = 8; $0.format = .float32; $0.packetSize = 9000; $0.ipVersion = .ipv6; $0.clientName = "envoi" })
        XCTAssertEqual(c.arguments, ["--jname", "envoi", "--chan", "8", "--float", "--mtu", "9000", "--ipv6", "10.10.10.1", "9999"])
        XCTAssertEqual(BridgeCommand(sender: sender { $0.format = .bits16 }).arguments.contains("--16bit"), true)
    }

    func testTheReceiverOptions() {
        let c = BridgeCommand(receiver: receiver { $0.automaticChannels = false; $0.channels = [1, 2, 3, 4, 7]; $0.bufferMilliseconds = 30; $0.filterDelay = 48; $0.ipVersion = .ipv4 })
        XCTAssertEqual(c.arguments, ["--jname", "zita-n2j", "--chan", "1-4,7", "--buff", "30", "--filt", "48", "--info", "--ipv4", "10.10.10.1", "9999"])
    }

    func testMulticastAddsTheInterfaceAfterThePort() {
        XCTAssertEqual(BridgeCommand(sender: sender { $0.address = "224.0.0.9"; $0.multicast = true; $0.interface = "en7"; $0.hops = 3 }).arguments.suffix(5),
                       ["--hops", "3", "224.0.0.9", "9999", "en7"])
        XCTAssertEqual(BridgeCommand(receiver: receiver { $0.address = "224.0.0.9"; $0.multicast = true; $0.interface = "en7" }).arguments.suffix(3),
                       ["224.0.0.9", "9999", "en7"])
    }

    func testTheHopsOfASingleHopAndOfAUnicastLinkAreNotSaid() {
        XCTAssertFalse(BridgeCommand(sender: sender { $0.hops = 5 }).arguments.contains("--hops"), "unicast does not use hops")
        XCTAssertFalse(BridgeCommand(sender: sender { $0.multicast = true; $0.interface = "en7" }).arguments.contains("--hops"))
    }

    func testAJackServerCanBeNamed() {
        XCTAssertEqual(BridgeCommand(receiver: receiver(), jackServer: "essai").arguments.prefix(4), ["--jname", "zita-n2j", "--jserv", "essai"])
        XCTAssertFalse(BridgeCommand(receiver: receiver()).arguments.contains("--jserv"))
    }

    func testTheDisplayQuotesWhatNeedsIt() {
        let c = BridgeCommand(sender: sender { $0.clientName = "mon envoi"; $0.address = "it's.local" })
        XCTAssertEqual(c.display(), "zita-j2n --jname 'mon envoi' --chan 2 --24bit 'it'\\''s.local' 9999")
    }

    // MARK: Address format

    func testWhatIsTypedInAnAddressFieldIsAnAddressOrAName() {
        for ok in ["10.10.10.1", "169.254.81.9", "0.0.0.0", "224.0.0.9"] { XCTAssertEqual(AddressCheck.syntax(of: ok), .ipv4, ok) }
        for ok in ["fe80::1", "fe80::1873:3dbc:1c96:41ce%en8", "::1", "ff02::1", "2001:db8::1", "fe80::1%bridge0"] { XCTAssertEqual(AddressCheck.syntax(of: ok), .ipv6, ok) }
        for ok in ["studio.local", "branquignole.com", "mac-mini", "a.b.c", "Studio_A.example.org", "studio.local."] { XCTAssertEqual(AddressCheck.syntax(of: ok), .hostname, ok) }
        XCTAssertEqual(AddressCheck.syntax(of: "  10.10.10.1  "), .ipv4); XCTAssertEqual(AddressCheck.syntax(of: ""), .empty); XCTAssertEqual(AddressCheck.syntax(of: "   "), .empty)
        for bad in ["10.10.10.999", "10.10.10", "10.10.10.1.1", "1.2.3", "mon adresse", "a..b", "-studio", "studio-", "école.fr", "fe80::zz", "fe80::1%", "fe80::1%en 8",
                    "1:2:3:4:5:6:7:8:9", "http://studio", "10.10.10.1:9999", "a@b", "mac!"] {
            XCTAssertEqual(AddressCheck.syntax(of: bad), .invalid, bad)
        }
    }

    func testAnInvalidAddressIsAnIssueOfTheSettings() {
        XCTAssertEqual(sender { $0.address = "10.10.10.999" }.issues, [.invalidAddress])
        XCTAssertEqual(receiver { $0.address = "mon adresse" }.issues, [.invalidAddress])
        XCTAssertEqual(sender { $0.address = "" }.issues, [.emptyAddress])
        XCTAssertEqual(sender { $0.address = "studio.local" }.issues, [], "a name is judged by whether it is found, not by its form")
    }

    // MARK: Multicast addresses

    func testMulticastGroupsAreRecognised() {
        for group in ["224.0.0.9", "239.255.255.250", " 232.1.2.3 ", "ff02::1", "FF05::abcd"] { XCTAssertTrue(MulticastAddress.isGroup(group), group) }
        for other in ["10.10.10.1", "223.255.255.255", "240.0.0.1", "192.168.1.20", "fe80::1", "", "224.0.0", "224.0.0.300", "studio.local"] {
            XCTAssertFalse(MulticastAddress.isGroup(other), other)
        }
        XCTAssertTrue(MulticastAddress.isNumeric("10.10.10.1")); XCTAssertTrue(MulticastAddress.isNumeric("fe80::1"))
        XCTAssertFalse(MulticastAddress.isNumeric("studio.local")); XCTAssertFalse(MulticastAddress.isNumeric("10.10.10"))
    }

    func testTheAddressDecidesWhetherTheLinkIsMulticast() async {
        let yes = await MulticastAddress.isGroupResolving("239.1.2.3"); XCTAssertEqual(yes, true)
        let v6 = await MulticastAddress.isGroupResolving("ff02::1"); XCTAssertEqual(v6, true)
        let no = await MulticastAddress.isGroupResolving("10.10.10.1"); XCTAssertEqual(no, false)
        let local = await MulticastAddress.isGroupResolving("localhost"); XCTAssertEqual(local, false, "a name is resolved, and it is not a group")
        let unknown = await MulticastAddress.isGroupResolving("no.such.host.invalid"); XCTAssertNil(unknown)
        let empty = await MulticastAddress.isGroupResolving("  "); XCTAssertNil(empty)
    }

    // MARK: Channel lists

    func testChannelListsAreWrittenAsTheProgramsReadThem() {
        XCTAssertEqual(ChannelList.format([1, 2]), "1,2")
        XCTAssertEqual(ChannelList.format([1, 2, 3]), "1-3")
        XCTAssertEqual(ChannelList.format([5, 1, 2, 3, 9, 10]), "1-3,5,9,10")
        XCTAssertEqual(ChannelList.format(Array(1...64)), "1-64")
    }

    func testChannelListsAreReadLikeTheProgramsDo() {
        XCTAssertEqual(ChannelList.parse("1,2"), [1, 2])
        XCTAssertEqual(ChannelList.parse("1-3,5"), [1, 2, 3, 5])
        XCTAssertEqual(ChannelList.parse(" 2 , 4 - 6 "), [2, 4, 5, 6])
        for bad in ["", "0", "65", "2,1", "1,1", "3-3", "3-2", "1,,2", "a", "1-", "-3", "1.5"] {
            XCTAssertNil(ChannelList.parse(bad), "'\(bad)' is refused by the programs")
        }
        XCTAssertEqual(ChannelList.parse(ChannelList.format([1, 2, 3, 5, 9])), [1, 2, 3, 5, 9], "what is written can be read back")
    }

    // MARK: Checks

    func testDefaultSettingsNeedAnAddress() {
        XCTAssertEqual(SendSettings().issues, [.emptyAddress])
        XCTAssertEqual(ReceiveSettings().issues, [.emptyAddress])
        XCTAssertEqual(sender().issues, [])
        XCTAssertEqual(receiver().issues, [])
    }

    func testEveryLimitOfTheProgramsIsChecked() {
        XCTAssertEqual(sender { $0.port = 0 }.issues, [.portOutOfRange])
        XCTAssertEqual(sender { $0.port = 65536 }.issues, [.portOutOfRange])
        XCTAssertEqual(sender { $0.channels = 65 }.issues, [.channelsOutOfRange])
        XCTAssertEqual(sender { $0.packetSize = 100 }.issues, [.packetSizeOutOfRange])
        XCTAssertEqual(sender { $0.multicast = true }.issues, [.multicastNeedsInterface])
        XCTAssertEqual(sender { $0.clientName = " " }.issues, [.emptyClientName])
        XCTAssertEqual(receiver { $0.bufferMilliseconds = 4001 }.issues, [.bufferOutOfRange])
        XCTAssertEqual(receiver { $0.bufferMilliseconds = -1 }.issues, [.bufferOutOfRange])
        XCTAssertEqual(receiver { $0.filterDelay = 15 }.issues, [.filterOutOfRange])
        XCTAssertEqual(receiver { $0.filterDelay = 97 }.issues, [.filterOutOfRange])
        XCTAssertEqual(receiver { $0.filterDelay = 16 }.issues, [])
        XCTAssertEqual(receiver { $0.automaticChannels = false; $0.channels = [] }.issues, [.channelsOutOfRange])
        XCTAssertEqual(receiver { $0.automaticChannels = false; $0.channels = [1, 65] }.issues, [.channelsOutOfRange])
        XCTAssertEqual(receiver { $0.automaticChannels = false; $0.channels = [2, 2] }.issues, [.channelsOutOfRange])
    }

    // MARK: Automatic channels

    func testAnAutomaticReceiverTakesTheChannelsTheSenderHadLastTime() {
        var r = receiver()
        XCTAssertTrue(r.automaticChannels)
        XCTAssertEqual(r.effectiveChannels, [1, 2], "stereo the first time")
        r.knownSenderChannels = 8
        XCTAssertEqual(r.effectiveChannels, Array(1...8))
        XCTAssertEqual(BridgeCommand(receiver: r).arguments.prefix(4).suffix(2), ["--chan", "1-8"])
        r.knownSenderChannels = 500
        XCTAssertEqual(r.effectiveChannels.count, 64, "never more than the programs take")
        r.knownSenderChannels = 0
        XCTAssertEqual(r.effectiveChannels, [1])
    }

    func testChosenChannelsAreUsedWhenNotAutomatic() {
        var r = receiver { $0.automaticChannels = false; $0.channels = [9, 10, 11] }
        r.knownSenderChannels = 8
        XCTAssertEqual(r.effectiveChannels, [9, 10, 11])
        XCTAssertEqual(BridgeCommand(receiver: r).arguments.prefix(4).suffix(2), ["--chan", "9-11"])
    }

    func testSettingsSavedByAnEarlierVersionStillLoad() throws {
        // A receiver saved before the channels became automatic: no key for them.
        let old = Data(#"{"address":"10.10.10.1","port":9999,"channels":[1,2],"bufferMilliseconds":20,"multicast":false,"interface":"","ipVersion":"automatic","clientName":"zita-n2j"}"#.utf8)
        let r = try JSONDecoder().decode(ReceiveSettings.self, from: old)
        XCTAssertEqual(r.address, "10.10.10.1"); XCTAssertEqual(r.bufferMilliseconds, 20)
        XCTAssertTrue(r.automaticChannels); XCTAssertEqual(r.knownSenderChannels, 2)
        XCTAssertEqual(try JSONDecoder().decode(ReceiveSettings.self, from: Data("{}".utf8)), ReceiveSettings(), "an empty record is the defaults")
    }

    func testSettingsSurviveBeingSaved() throws {
        var r = receiver { $0.channels = [1, 3]; $0.filterDelay = 40; $0.multicast = true; $0.interface = "en7" }
        r.ipVersion = .ipv6
        XCTAssertEqual(try JSONDecoder().decode(ReceiveSettings.self, from: JSONEncoder().encode(r)), r)
        let s = sender { $0.format = .float32 }
        XCTAssertEqual(try JSONDecoder().decode(SendSettings.self, from: JSONEncoder().encode(s)), s)
    }
}
