// SPDX-License-Identifier: GPL-2.0-or-later

import XCTest
@testable import JackCaptureKit

final class DiskGuardTests: XCTestCase {
    func testTheTimeLeftIsTheRoomAboveTheReserveOverTheRate() {
        // 20 GB free, 10 GB kept, 1 MB per second: 10 000 s.
        XCTAssertEqual(DiskGuard.secondsLeft(free: 20_000_000_000, reserve: 10_000_000_000, bytesPerSecond: 1_000_000), 10_000)
        XCTAssertEqual(DiskGuard.secondsLeft(free: 5_000_000_000, reserve: 10_000_000_000, bytesPerSecond: 1_000_000), 0)
        XCTAssertNil(DiskGuard.secondsLeft(free: 1, reserve: 0, bytesPerSecond: 0))
    }

    func testTheReserveInBytes() {
        XCTAssertEqual(DiskGuard.reserveBytes(gigabytes: 10), 10_000_000_000)
        XCTAssertEqual(DiskGuard.reserveBytes(gigabytes: 0), 0)
        XCTAssertEqual(DiskGuard.reserveBytes(gigabytes: -3), 0)
    }

    func testTheRecordingIsStoppedAtTheReserve() {
        XCTAssertEqual(DiskGuard.verdict(free: 10_000_000_000, reserve: 10_000_000_000, bytesPerSecond: 1_000), .stop)
        XCTAssertEqual(DiskGuard.verdict(free: 9_999_999_999, reserve: 10_000_000_000, bytesPerSecond: 1_000), .stop)
    }

    func testTheNoticeComesWhenAQuarterOfAnHourIsLeft() {
        // 864 KB per second: a quarter of an hour is about 778 MB above the reserve.
        let rate = 864_000.0
        XCTAssertEqual(DiskGuard.verdict(free: 10_700_000_000, reserve: 10_000_000_000, bytesPerSecond: rate), .low)
        XCTAssertEqual(DiskGuard.verdict(free: 12_000_000_000, reserve: 10_000_000_000, bytesPerSecond: rate), .fine)
    }

    func testWithNoReserveTheRecordingIsNeverStoppedButTheNoticeStillComes() {
        XCTAssertEqual(DiskGuard.verdict(free: 100_000_000, reserve: 0, bytesPerSecond: 864_000), .low)
        XCTAssertEqual(DiskGuard.verdict(free: 0, reserve: 0, bytesPerSecond: 864_000), .low)
        XCTAssertEqual(DiskGuard.verdict(free: 500_000_000_000, reserve: 0, bytesPerSecond: 864_000), .fine)
    }
}

@MainActor
final class DiskReserveTests: XCTestCase {
    private func startable(_ model: RecorderModel, free: Int64) {
        model.jackIsAvailable = { true }
        model.executable = { URL(fileURLWithPath: "/usr/bin/true") }
        model.settings.folder = NSTemporaryDirectory()
        model.freeBytes = { free }
    }

    func testARecordingIsRefusedWhenTheDiskIsBelowTheReserve() {
        let model = RecorderModel()
        startable(model, free: 5_000_000_000)
        model.settings.diskReserveGigabytes = 10
        model.toggleRecording()
        XCTAssertEqual(model.phase, .configuration)
        XCTAssertNotNil(model.errorMessage)
    }

    func testTheReserveCanBeSwitchedOffBySettingItToZero() {
        let model = RecorderModel()
        startable(model, free: 5_000_000_000)
        model.settings.diskReserveGigabytes = 0
        model.executable = { nil }   // stops the start after the checks that are tested here, with its own message
        model.toggleRecording()
        XCTAssertEqual(model.errorMessage, String(localized: "Le programme jack_capture est introuvable."))
    }

    func testAFileUnderAFixedNameIsWrittenByOneSessionOnly() {
        let hub = CaptureHub()
        let first = RecorderModel(hub: hub), second = RecorderModel(hub: hub)
        for model in [first, second] {
            startable(model, free: 500_000_000_000)
            model.settings.numbering = false
            model.settings.name = "Take"
        }
        let url = second.settings.folderURL.appendingPathComponent("\(second.settings.baseName).\(second.settings.format.fileExtension)")
        XCTAssertTrue(hub.reserve(url, for: first.id))
        second.toggleRecording()
        XCTAssertEqual(second.phase, .configuration)
        XCTAssertEqual(second.errorMessage, String(localized: "Un autre enregistrement écrit déjà dans ce fichier. Changer le nom, ou activer la numérotation."))
        // Once the first is done the file is free again, and the same session may have it.
        hub.release(for: first.id)
        XCTAssertTrue(hub.reserve(url, for: second.id))
        XCTAssertTrue(hub.reserve(url, for: second.id))
    }
}
