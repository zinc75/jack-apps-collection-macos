// SPDX-License-Identifier: GPL-2.0-or-later

import XCTest
@testable import JackCaptureKit

final class SettingsTests: XCTestCase {
    func testChannelLimitFollowsTheFormat() {
        var s = CaptureSettings()
        s.setChannels(64)
        XCTAssertEqual(s.channels, 64)
        let change = s.setFormat(.flac)
        XCTAssertEqual(s.channels, 8)
        XCTAssertTrue(change.channelsReduced)
        s.setChannels(0)
        XCTAssertEqual(s.channels, 1)
        s.setFormat(.mp3)
        s.setChannels(5)
        XCTAssertEqual(s.channels, 2)
    }

    func testLimits() {
        XCTAssertEqual(CaptureFormat.wav.maxChannels, 1024)
        XCTAssertEqual(CaptureFormat.ogg.maxChannels, 255)
        XCTAssertEqual(CaptureFormat.opus.maxChannels, 255)
    }

    func testDepthFallsBackWhenTheFormatDoesNotOfferIt() {
        var s = CaptureSettings()
        s.depth = .float32
        s.setFormat(.flac)
        XCTAssertEqual(s.depth, .int24)
    }

    func testChannelsShrinkAndDropSources() {
        var s = CaptureSettings()
        s.setChannels(4)
        s.sources = [["a:1"], ["a:2"], ["a:3"], ["a:4"]]
        s.setChannels(2)
        XCTAssertEqual(s.sources.count, 2)
    }

    func testBaseNameCannotBePathOrOption() {
        var s = CaptureSettings()
        s.name = "  --help/x "
        XCTAssertEqual(s.baseName, "help-x")
        s.name = "---"
        XCTAssertEqual(s.baseName, "Prise")
        s.name = ""
        XCTAssertEqual(s.baseName, "Prise")
    }
}

final class CommandTests: XCTestCase {
    private func words(_ s: CaptureSettings) -> String { CaptureCommand(settings: s).arguments.joined(separator: " ") }

    func testDefaults() {
        XCTAssertEqual(words(CaptureSettings()), "-c 2 -jn Jack Capture -mc -b 24 -fp Prise_ -z 1")
    }

    func testSingleSourcePerChannelUsesPortsInOrder() {
        var s = CaptureSettings()
        s.sources = [["system:capture_1"], ["Reaper:out 2"]]
        let cmd = CaptureCommand(settings: s)
        XCTAssertEqual(Array(cmd.arguments.prefix(8)), ["-c", "2", "-jn", "Jack Capture", "-p", "system:capture_1", "-p", "Reaper:out 2"])
        XCTAssertTrue(cmd.connections.isEmpty)
        XCTAssertTrue(cmd.displayText.contains("-p \"Reaper:out 2\""))
        XCTAssertTrue(cmd.displayText.contains("-p system:capture_1"))
    }

    func testSeveralSourcesInOneChannelAreConnectedByTheApplication() {
        var s = CaptureSettings()
        s.sources = [["a:1", "b:1"], ["a:2"]]
        let cmd = CaptureCommand(settings: s)
        XCTAssertTrue(cmd.arguments.contains("-mc"))
        XCTAssertFalse(cmd.arguments.contains("-p"))
        XCTAssertEqual(cmd.connections, [
            .init(source: "a:1", destination: "Jack Capture:input1"),
            .init(source: "b:1", destination: "Jack Capture:input1"),
            .init(source: "a:2", destination: "Jack Capture:input2"),
        ])
        XCTAssertTrue(cmd.displayText.contains("jack_connect a:1 \"Jack Capture:input1\""))
    }

    func testAnInputPortIsExpandedToWhatFeedsItWhenTheApplicationConnects() {
        var s = CaptureSettings()
        s.sources = [["system:playback_1", "a:1"], ["system:playback_2"]]
        let cmd = CaptureCommand(settings: s, inputConnections: [
            "system:playback_1": ["b:1", "c:1"], "system:playback_2": [],
        ])
        XCTAssertTrue(cmd.arguments.contains("-mc"))
        XCTAssertEqual(cmd.connections, [
            .init(source: "b:1", destination: "Jack Capture:input1"),
            .init(source: "c:1", destination: "Jack Capture:input1"),
            .init(source: "a:1", destination: "Jack Capture:input1"),
        ])
    }

    func testAChannelWithoutSourceAmongOthersCannotUsePositionalPorts() {
        var s = CaptureSettings()
        s.sources = [[], ["a:2"]]
        let cmd = CaptureCommand(settings: s)
        XCTAssertTrue(cmd.arguments.contains("-mc"))
        XCTAssertEqual(cmd.connections, [.init(source: "a:2", destination: "Jack Capture:input2")])
    }

    func testNoAutoConnectMeansManualConnections() {
        var s = CaptureSettings()
        s.autoConnect = false
        s.sources = [["a:1"], ["a:2"]]
        let cmd = CaptureCommand(settings: s)
        XCTAssertTrue(cmd.arguments.contains("-mc"))
        XCTAssertTrue(cmd.connections.isEmpty)
    }

    func testClientNameIsPassedAndUsedForConnections() {
        var s = CaptureSettings()
        s.clientName = "capture2"
        s.sources = [["a:1", "b:1"], []]
        let cmd = CaptureCommand(settings: s)
        XCTAssertEqual(cmd.arguments.prefix(4), ["-c", "2", "-jn", "capture2"])
        XCTAssertEqual(cmd.connections.first?.destination, "capture2:input1")
    }

    func testClientNameIsCleaned() {
        var s = CaptureSettings()
        s.clientName = "  my:rec "
        XCTAssertEqual(s.jackClientName, "myrec")
        s.clientName = " : "
        XCTAssertEqual(s.jackClientName, "Jack Capture")
        XCTAssertTrue(CaptureCommand(settings: s).arguments.contains("-jn"))
        s.clientName = "jack_capture"   // the name the program picks itself: nothing to pass
        XCTAssertFalse(CaptureCommand(settings: s).arguments.contains("-jn"))
    }

    func testFormats() {
        var s = CaptureSettings()
        s.setFormat(.rf64); s.depth = .int16
        XCTAssertEqual(words(s), "-c 2 -jn Jack Capture -mc -f rf64 -b 16 -fp Prise_ -z 1")
        s.setFormat(.wav); s.depth = .float32
        XCTAssertEqual(words(s), "-c 2 -jn Jack Capture -mc -fp Prise_ -z 1")
        s.setFormat(.flac)
        XCTAssertEqual(words(s), "-c 2 -jn Jack Capture -mc -f flac -b 24 -fp Prise_ -z 1")
        s.setFormat(.mp3); s.mp3Bitrate = 256
        XCTAssertEqual(words(s), "-c 2 -jn Jack Capture -mc -mp3 -mp3b 256 -fp Prise_ -z 1")
        s.setFormat(.ogg); s.oggQuality = 70
        XCTAssertEqual(words(s), "-c 2 -jn Jack Capture -mc -f ogg -oq 0.70 -fp Prise_ -z 1")
        s.setFormat(.opus)
        XCTAssertEqual(words(s), "-c 2 -jn Jack Capture -mc -f opus -fp Prise_ -z 1")
    }

    func testDurationsAreInSeconds() {
        var s = CaptureSettings()
        s.scheduledStop = true; s.durationSeconds = 6
        XCTAssertTrue(words(s).contains("-d 6 "))
        s.durationSeconds = 0
        XCTAssertTrue(words(s).contains("-d 1 "), "never less than a second")
        s.rotatesFiles = true; s.rotationSeconds = 30
        XCTAssertTrue(CaptureCommand(settings: s, sampleRate: 48_000).arguments.contains("1440000"))
    }

    func testMinutesAndSecondsMakeOneDuration() {
        XCTAssertEqual(TimeSpan.seconds(minutes: 4, seconds: 25), 265)
        XCTAssertEqual(TimeSpan.seconds(minutes: 1, seconds: 90), 150, "seconds past 59 carry over")
        XCTAssertEqual(TimeSpan.seconds(minutes: 0, seconds: 0), 1, "never less than a second")
        XCTAssertEqual(TimeSpan.seconds(minutes: 5000, seconds: 0), 86_400, "a day at most")
    }

    func testDurationText() {
        XCTAssertEqual(TimeSpan.text(265), "4 min 25 s")
        XCTAssertEqual(TimeSpan.text(6), "6 s")
        XCTAssertEqual(TimeSpan.text(600), "10 min")
        XCTAssertEqual(TimeSpan.text(0), "0 s")
    }

    func testStartAndStopOptions() {
        var s = CaptureSettings()
        s.startMode = .transport
        s.scheduledStop = true; s.durationSeconds = 120
        s.timemachine = true; s.timemachineSeconds = 5
        s.writesTimeFile = true
        s.rotatesFiles = true; s.rotationSeconds = 600
        s.bufferSeconds = 8
        s.oscEnabled = true; s.oscPort = 9000
        XCTAssertEqual(CaptureCommand(settings: s, sampleRate: 44_100).arguments.joined(separator: " "),
                       "-c 2 -jn Jack Capture -mc -b 24 -jt -d 120 -tm -tmpb 5 -S -Rf 26460000 -B 8 -O 9000 -fp Prise_ -z 1")
        s.startMode = .freewheel
        XCTAssertTrue(words(s).contains("-jf"))
    }

    func testFixedFileNameWithoutNumbering() {
        var s = CaptureSettings()
        s.numbering = false
        s.name = "Mon prise"
        s.setFormat(.aiff)
        let cmd = CaptureCommand(settings: s)
        XCTAssertEqual(cmd.arguments.last, "Mon prise.aiff")
        XCTAssertTrue(cmd.displayText.hasSuffix("\"Mon prise.aiff\""))
    }

    func testDirectoryAndQuoting() {
        var s = CaptureSettings()
        XCTAssertEqual(CaptureCommand(settings: s).directory, "~/Music/Jack Capture")
        XCTAssertTrue(CaptureCommand(settings: s).displayText.hasPrefix("cd ~/Music/Jack\\ Capture\n"))
        s.folder = "~/Music/Captures"
        XCTAssertTrue(CaptureCommand(settings: s).displayText.hasPrefix("cd ~/Music/Captures\n"))
        s.folder = "~"
        XCTAssertTrue(CaptureCommand(settings: s).displayText.hasPrefix("cd ~\n"))
        s.folder = "/Volumes/Disque $x"
        XCTAssertEqual(CaptureCommand(settings: s).directory, "/Volumes/Disque $x")
        XCTAssertTrue(CaptureCommand(settings: s).displayText.hasPrefix("cd /Volumes/Disque\\ \\$x\n"))
    }
}

final class EstimateTests: XCTestCase {
    func testPcmRate() {
        let s = CaptureSettings()   // 2 channels, 24 bits, 48 kHz
        XCTAssertEqual(RecordingEstimate.bytesPerSecond(s), 288_000)
    }

    func testCompressedRates() {
        var s = CaptureSettings()
        s.setFormat(.mp3); s.mp3Bitrate = 192
        XCTAssertEqual(RecordingEstimate.bytesPerSecond(s), 24_000)
        s.setFormat(.flac)
        XCTAssertEqual(RecordingEstimate.bytesPerSecond(s), 288_000 * 0.55, accuracy: 0.001)
    }

    func testNextFreeNameTakesTheFirstGap() {
        let s = CaptureSettings()
        let taken: Set<String> = ["Prise_01.wav", "Prise_02.wav", "Prise_04.wav"]
        XCTAssertEqual(FileNaming.nextName(s) { taken.contains($0) }, "Prise_03.wav")
        XCTAssertEqual(FileNaming.nextName(s) { _ in false }, "Prise_01.wav")
    }

    func testNextNameWithoutNumbering() {
        var s = CaptureSettings()
        s.numbering = false
        s.setFormat(.flac)
        XCTAssertEqual(FileNaming.nextName(s) { _ in true }, "Prise.flac")
    }

    func testNextNameLooksAtTheDisk() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("jc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        var s = CaptureSettings()
        s.folder = dir.path
        FileManager.default.createFile(atPath: dir.appendingPathComponent("Prise_01.wav").path, contents: Data())
        XCTAssertEqual(FileNaming.nextName(s), "Prise_02.wav")
        XCTAssertNotNil(RecordingEstimate.availableBytes(at: dir.appendingPathComponent("not/yet")))
    }
}

final class IntegerInputTests: XCTestCase {
    func testTypedDigitsBecomeTheNumber() {
        XCTAssertEqual(IntegerInput.commit("64", current: 2, range: 1...1024), 64)
        XCTAssertEqual(IntegerInput.commit(" 12 voies", current: 2, range: nil), 12)
    }

    func testAnEmptyFieldKeepsTheCurrentValue() {
        XCTAssertEqual(IntegerInput.commit("", current: 2, range: 1...64), 2)
        XCTAssertEqual(IntegerInput.commit("abc", current: 5, range: 1...64), 5)
    }

    func testTheNumberStaysInsideItsRange() {
        XCTAssertEqual(IntegerInput.commit("500", current: 2, range: 1...64), 64)
        XCTAssertEqual(IntegerInput.commit("0", current: 2, range: 1...64), 1)
    }

    func testOnlyDigitsAreKeptWhileTyping() {
        XCTAssertEqual(IntegerInput.digits("6a4-"), "64")
    }
}
