// SPDX-License-Identifier: GPL-2.0-or-later

import XCTest
@testable import JackCaptureKit

final class FolderCheckTests: XCTestCase {
    private func temporaryFolder() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("jcf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testAnExistingWritableFolderIsFine() throws {
        XCTAssertNil(FolderCheck.problem(for: try temporaryFolder()))
    }

    func testAFolderToCreateBelowAnExistingOneIsFine() throws {
        XCTAssertNil(FolderCheck.problem(for: try temporaryFolder().appendingPathComponent("a/b")))
    }

    func testAnUnpluggedVolumeIsNamed() {
        let url = URL(fileURLWithPath: "/Volumes/Disque-absent-\(UUID().uuidString)/Prises")
        guard case .volumeNotMounted(let name)? = FolderCheck.problem(for: url) else { return XCTFail("no problem") }
        XCTAssertTrue(name.hasPrefix("Disque-absent-"))
    }

    func testAFileInPlaceOfTheFolderIsRefused() throws {
        let file = try temporaryFolder().appendingPathComponent("f.txt")
        try Data("x".utf8).write(to: file)
        XCTAssertEqual(FolderCheck.problem(for: file), .notADirectory)
        XCTAssertEqual(FolderCheck.problem(for: file.appendingPathComponent("sub")), .notADirectory)
    }

    func testAFolderWithoutWritePermissionIsRefused() throws {
        let dir = try temporaryFolder()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path) }
        XCTAssertEqual(FolderCheck.problem(for: dir), .notWritable)
        XCTAssertEqual(FolderCheck.problem(for: dir.appendingPathComponent("new")), .notWritable)
    }

    func testTooLittleFreeSpaceIsRefused() throws {
        let dir = try temporaryFolder()
        guard case .noSpace? = FolderCheck.problem(for: dir, minimumFree: Int64.max) else { return XCTFail("no problem") }
    }
}

final class ClientNameTests: XCTestCase {
    func testAFreeNameIsKept() {
        XCTAssertEqual(JackGraph.freeName("Jack Capture", taken: ["system", "Reaper"]), "Jack Capture")
    }

    func testATakenNameGetsTheFirstFreeNumber() {
        XCTAssertEqual(JackGraph.freeName("Jack Capture", taken: ["Jack Capture"]), "Jack Capture 2")
        XCTAssertEqual(JackGraph.freeName("Jack Capture", taken: ["Jack Capture", "Jack Capture 2"]), "Jack Capture 3")
    }
}

@MainActor
final class QuitAndServerLossTests: XCTestCase {
    private func model(script body: String) throws -> RecorderModel {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("jcq-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("fake_capture.sh")
        try ("#!/bin/bash\n" + body).write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        let model = RecorderModel()
        model.settings.folder = dir.path
        model.executable = { url }
        model.jackIsAvailable = { true }
        return model
    }

    private func wait(_ condition: @MainActor () -> Bool, timeout: TimeInterval = 8) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline { try? await Task.sleep(for: .milliseconds(50)) }
    }

    private let recording = #"""
    trap 'printf "\033[31mFinished.\033[0m\n" >&2; touch "$PWD/closed"; exit 0' INT
    head -c 20000 /dev/zero > "$PWD/Prise_01.wav"
    printf '\033[31m>>> Recording to "Prise_01.wav". Press <Return> or <Ctrl-C> to stop.\n\033[0m' >&2
    while true; do printf 'Buffer: 4.01s./4.01s    Time: 0.00m.   DHP: [ ]  Overruns: 0  Xruns: 0\n'; sleep 0.1; done
    """#

    func testQuittingWaitsForTheFileToBeClosed() async throws {
        let model = try model(script: recording)
        model.toggleRecording()
        await wait { model.outputFile != nil }
        XCTAssertTrue(model.isBusy)
        XCTAssertTrue(model.isWriting)
        var released = false
        model.stopForQuit { released = true }
        XCTAssertFalse(released, "released before jack_capture ended")
        await wait { released }
        XCTAssertTrue(released)
        XCTAssertTrue(FileManager.default.fileExists(atPath: model.settings.folderURL.appendingPathComponent("closed").path))
        XCTAssertEqual(model.phase, .done)
    }

    func testQuittingWithNothingRunningIsImmediate() throws {
        let model = try model(script: recording)
        var released = false
        model.stopForQuit { released = true }
        XCTAssertTrue(released)
        XCTAssertFalse(model.isBusy)
    }

    func testAServerLossGivesAClearWarning() async throws {
        let model = try model(script: #"""
        head -c 20000 /dev/zero > "$PWD/Prise_01.wav"
        printf '\033[31m>>> Recording to "Prise_01.wav". Press <Return> or <Ctrl-C> to stop.\n\033[0m' >&2
        sleep 0.4
        printf 'jack_capture: JACK shutdown.\n' >&2
        printf '\033[31mFinished.\033[0m\n' >&2
        exit 0
        """#)
        model.toggleRecording()
        await wait { model.phase == .done }
        XCTAssertEqual(model.phase, .done)
        XCTAssertTrue(model.warnings.first?.contains("JACK") ?? false)
        XCTAssertFalse(model.warnings.contains { $0.contains("JACK shutdown") }, "the raw line is replaced by the sentence")
        XCTAssertNotNil(model.summary)
    }

    func testARotatedRecordingIsSeveralFiles() async throws {
        let model = try model(script: #"""
        trap 'printf "\033[31mFinished.\033[0m\n" >&2; exit 0' INT
        head -c 3000 /dev/zero > "$PWD/Prise_01.wav.00.wav"
        head -c 2000 /dev/zero > "$PWD/Prise_01.wav.01.wav"
        head -c 1000 /dev/zero > "$PWD/Prise_01.wav.notapart"
        printf '\033[31m>>> Recording to "Prise_01.wav". Press <Return> or <Ctrl-C> to stop.\n\033[0m' >&2
        while true; do printf 'Buffer: 4.01s./4.01s    Time: 0.00m.   DHP: [ ]  Overruns: 0  Xruns: 0\n'; sleep 0.1; done
        """#)
        model.settings.rotatesFiles = true
        model.toggleRecording()
        await wait { model.outputFile != nil }
        XCTAssertEqual(model.recordedURL?.lastPathComponent, "Prise_01.wav.00.wav")
        XCTAssertEqual(model.recordedFiles.map(\.lastPathComponent), ["Prise_01.wav.00.wav", "Prise_01.wav.01.wav"])
        model.toggleRecording()
        await wait { model.phase == .done }
        XCTAssertEqual(model.bytesWritten, 5000)
        XCTAssertEqual(model.summary?.partCount, 2)
        XCTAssertEqual(model.summary?.bytes, 5000)
    }

    func testAnUnusableFolderStopsBeforeLaunching() throws {
        let model = try model(script: recording)
        model.settings.folder = "/Volumes/Disque-absent-\(UUID().uuidString)/Prises"
        model.toggleRecording()
        XCTAssertEqual(model.phase, .configuration)
        XCTAssertNotNil(model.errorMessage)
    }
}
