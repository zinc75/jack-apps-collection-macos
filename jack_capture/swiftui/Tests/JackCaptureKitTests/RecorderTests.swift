// SPDX-License-Identifier: GPL-2.0-or-later

import XCTest
@testable import JackCaptureKit

final class RecorderPhaseTests: XCTestCase {
    func testConfigurationIsLockedOnlyWhileRecording() {
        XCTAssertFalse(RecorderPhase.configuration.isLocked)
        XCTAssertTrue(RecorderPhase.armed.isLocked)
        XCTAssertTrue(RecorderPhase.recording.isLocked)
        XCTAssertTrue(RecorderPhase.stopping.isLocked)
        XCTAssertFalse(RecorderPhase.done.isLocked)
    }

    func testStopSymbolFollowsTheLock() {
        for phase in [RecorderPhase.configuration, .armed, .recording, .stopping, .done] {
            XCTAssertEqual(phase.showsStopSymbol, phase.isLocked)
        }
    }
}

final class TimeFormatTests: XCTestCase {
    func testClock() {
        XCTAssertEqual(TimeFormat.clock(0), "00:00:00")
        XCTAssertEqual(TimeFormat.clock(83.9), "00:01:23")
        XCTAssertEqual(TimeFormat.clock(3723), "01:02:03")
        XCTAssertEqual(TimeFormat.clock(-5), "00:00:00")
    }

    func testTenth() {
        XCTAssertEqual(TimeFormat.tenth(1.34), 3)
        XCTAssertEqual(TimeFormat.tenth(59.99), 9)
        XCTAssertEqual(TimeFormat.tenth(0), 0)
    }
}

@MainActor
final class RecorderModelTests: XCTestCase {
    /// A model that runs a script in place of jack_capture, as if JACK was running.
    private func model(script body: String) throws -> RecorderModel {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("jcm-\(UUID().uuidString)")
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

    private let recording = #"""
    trap 'printf "\033[31mFinished.\033[0m\n" >&2; exit 0' INT
    head -c 20000 /dev/zero > "$PWD/Prise_01.wav"
    printf '\033[31m>>> Recording to "Prise_01.wav". Press <Return> or <Ctrl-C> to stop.\n\033[0m' >&2
    while true; do printf 'Buffer: 4.01s./4.01s    Time: 0.00m.   DHP: [ ]  Overruns: 0  Xruns: 0\n'; sleep 0.1; done
    """#

    private func wait(_ condition: @MainActor () -> Bool, timeout: TimeInterval = 8) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline { try? await Task.sleep(for: .milliseconds(50)) }
    }

    func testStartThenStopReachesDoneWithTheFileOfJackCapture() async throws {
        let model = try model(script: recording)
        XCTAssertEqual(model.phase, .configuration)
        model.toggleRecording()
        XCTAssertEqual(model.phase, .recording)
        XCTAssertEqual(model.view, .recording)
        await wait { model.outputFile != nil && model.status != nil }
        XCTAssertEqual(model.outputFile, "Prise_01.wav")
        XCTAssertEqual(model.status?.bufferTotal, 4.01)
        model.toggleRecording()
        XCTAssertEqual(model.phase, .stopping)
        model.toggleRecording()                    // ignored while the buffer is being written
        XCTAssertEqual(model.phase, .stopping)
        await wait { model.phase == .done }
        XCTAssertEqual(model.phase, .done)
        XCTAssertEqual(model.recordedURL?.lastPathComponent, "Prise_01.wav")
        XCTAssertGreaterThan(model.bytesWritten, 0)
        let summary = try XCTUnwrap(model.summary)
        XCTAssertEqual(summary.file.lastPathComponent, "Prise_01.wav")
        XCTAssertTrue(summary.commandText.contains("jack_capture") || summary.commandText.hasPrefix("cd "))
        XCTAssertEqual(summary.settings, model.settings)
        XCTAssertGreaterThan(summary.endedAt, summary.startedAt)
        XCTAssertEqual(summary.fileInfo?.container, "Unknown")   // a file of zeros is not audio the system can read
        XCTAssertNil(summary.fileInfo?.frames)
    }

    func testWithoutJackItDoesNotStartAndSaysWhy() throws {
        let model = try model(script: recording)
        model.jackIsAvailable = { false }
        model.toggleRecording()
        XCTAssertEqual(model.phase, .configuration)
        XCTAssertNotNil(model.errorMessage)
    }

    func testAMissingProgramIsReported() throws {
        let model = try model(script: recording)
        model.executable = { nil }
        model.toggleRecording()
        XCTAssertEqual(model.phase, .configuration)
        XCTAssertNotNil(model.errorMessage)
    }

    func testAProgramThatFailsAtOnceGivesItsMessageAndGoesBackToTheConfiguration() async throws {
        let model = try model(script: "echo 'Could not open the file' >&2\nexit 1\n")
        model.toggleRecording()
        await wait { model.errorMessage != nil }
        XCTAssertEqual(model.errorMessage, "Could not open the file")
        XCTAssertEqual(model.phase, .configuration)
        XCTAssertEqual(model.view, .recording)
    }

    func testTimemachineIsArmedUntilTheRedButtonIsPressedAgain() async throws {
        let model = try model(script: """
        trap 'printf "Finished.\\n" >&2; exit 0' INT
        printf '>>> Waiting to start recording of "Tm_01.wav"\\n' >&2
        read line
        head -c 20000 /dev/zero > "$PWD/Tm_01.wav"
        while true; do sleep 0.1; done
        """)
        model.settings.timemachine = true
        model.toggleRecording()
        XCTAssertEqual(model.phase, .armed)
        XCTAssertEqual(model.armedReason, .timemachine)
        await wait { model.outputFile != nil }
        XCTAssertEqual(model.outputFile, "Tm_01.wav")
        model.toggleRecording()                    // the second press starts the file
        XCTAssertEqual(model.phase, .recording)
        model.toggleRecording()
        await wait { model.phase == .done }
        XCTAssertEqual(model.phase, .done)
    }

    private func ephemeralDefaults() -> UserDefaults {
        let suite = "jc-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testTheSettingsComeBackAtTheNextLaunch() {
        let defaults = ephemeralDefaults()
        let first = RecorderModel(defaults: defaults)
        first.settings.setFormat(.flac)
        first.settings.setChannels(6)
        first.settings.name = "Concert"
        first.settings.sources = [["a:1"], ["b:2", "c:1"]]
        first.settings.writesTimeFile = true
        first.saveSettings()
        let second = RecorderModel(defaults: defaults)
        XCTAssertEqual(second.settings, first.settings)
        XCTAssertEqual(second.settings.format, .flac)
        XCTAssertEqual(second.settings.channels, 6)
    }

    func testUnreadableSavedSettingsGiveTheDefaults() {
        let defaults = ephemeralDefaults()
        defaults.set(Data("not json".utf8), forKey: "settings.v1")
        XCTAssertEqual(RecorderModel(defaults: defaults).settings, CaptureSettings())
    }

    func testSavedSettingsOutsideTheLimitsAreBroughtBack() throws {
        let defaults = ephemeralDefaults()
        var wild = CaptureSettings()
        wild.setChannels(300)
        defaults.set(try JSONEncoder().encode(wild), forKey: "settings.v1")
        // A hand-edited file may hold FLAC with 300 channels.
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: try JSONEncoder().encode(wild)) as? [String: Any])
        json["format"] = "flac"
        defaults.set(try JSONSerialization.data(withJSONObject: json), forKey: "settings.v1")
        let model = RecorderModel(defaults: defaults)
        XCTAssertEqual(model.settings.format, .flac)
        XCTAssertEqual(model.settings.channels, 8)
    }

    func testSettingsFromAnEarlierVersionStillLoad() throws {
        // Minutes in a decimal field, as the previous version wrote them, and a setting this one did not know.
        let old = #"{"channels": 4, "name": "Concert", "scheduledStop": true, "durationMinutes": 0.1, "rotationMinutes": 15, "gone": 1}"#
        let defaults = ephemeralDefaults()
        defaults.set(Data(old.utf8), forKey: "settings.v1")
        let settings = RecorderModel(defaults: defaults).settings
        XCTAssertEqual(settings.channels, 4)
        XCTAssertEqual(settings.name, "Concert")
        XCTAssertEqual(settings.durationSeconds, 6)
        XCTAssertEqual(settings.rotationSeconds, 900)
        XCTAssertEqual(settings.folder, CaptureSettings().folder, "what was not saved takes its default")
    }

    func testTheFirstLaunchSendsTheRedButtonToTheChannels() async throws {
        let defaults = ephemeralDefaults()
        let model = try model(script: recording)
        let first = RecorderModel(defaults: defaults)
        XCTAssertFalse(first.isConfigured)
        first.executable = model.executable
        first.jackIsAvailable = { true }
        first.settings.folder = model.settings.folder
        first.toggleRecording()
        XCTAssertEqual(first.phase, .configuration, "nothing started")
        XCTAssertEqual(first.view, .channels)
        XCTAssertTrue(first.isConfigured, "the page was seen")
        // Seen once, it stays so at the next launch, even with settings never saved.
        XCTAssertTrue(RecorderModel(defaults: defaults).isConfigured)
    }

    func testSavedSettingsMeanAnEarlierLaunch() {
        let defaults = ephemeralDefaults()
        let first = RecorderModel(defaults: defaults)
        first.saveSettings()
        XCTAssertTrue(RecorderModel(defaults: defaults).isConfigured)
    }

    func testWithoutDefaultsTheRedButtonRecords() throws {
        XCTAssertTrue(RecorderModel().isConfigured)
    }

    func testWithoutDefaultsNothingIsKept() {
        let model = RecorderModel()
        model.settings.name = "x"
        model.saveSettings()   // no effect, no crash
        XCTAssertEqual(RecorderModel().settings, CaptureSettings())
    }

    func testNewRecordingGoesBackToTheConfiguration() async throws {
        let model = try model(script: recording)
        model.toggleRecording()
        await wait { model.outputFile != nil }
        model.toggleRecording()
        await wait { model.phase == .done }
        model.newRecording()
        XCTAssertEqual(model.phase, .configuration)
        XCTAssertEqual(model.view, .recording)
        XCTAssertEqual(model.elapsed, 0)
        XCTAssertNil(model.outputFile)
    }
}
