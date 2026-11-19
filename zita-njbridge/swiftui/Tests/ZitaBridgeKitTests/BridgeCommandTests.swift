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
        let c = BridgeCommand(receiver: receiver { $0.channels = [1, 2, 3, 4, 7]; $0.bufferMilliseconds = 30; $0.filterDelay = 48; $0.ipVersion = .ipv4 })
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
        XCTAssertEqual(receiver { $0.channels = [] }.issues, [.channelsOutOfRange])
        XCTAssertEqual(receiver { $0.channels = [1, 65] }.issues, [.channelsOutOfRange])
        XCTAssertEqual(receiver { $0.channels = [2, 2] }.issues, [.channelsOutOfRange])
    }

    func testSettingsSurviveBeingSaved() throws {
        var r = receiver { $0.channels = [1, 3]; $0.filterDelay = 40; $0.multicast = true; $0.interface = "en7" }
        r.ipVersion = .ipv6
        XCTAssertEqual(try JSONDecoder().decode(ReceiveSettings.self, from: JSONEncoder().encode(r)), r)
        let s = sender { $0.format = .float32 }
        XCTAssertEqual(try JSONDecoder().decode(SendSettings.self, from: JSONEncoder().encode(s)), s)
    }
}
