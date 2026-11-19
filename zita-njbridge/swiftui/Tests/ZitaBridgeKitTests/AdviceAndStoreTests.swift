// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import ZitaBridgeKit

final class AdviceAndStoreTests: XCTestCase {
    // MARK: Buffer advice

    func testTheAdviceFollowsWhatWasMeasured() {
        XCTAssertEqual([64, 128, 256].map { BufferAdvice.recommendedMilliseconds(period: $0) }, [10, 10, 10])
        XCTAssertEqual(BufferAdvice.recommendedMilliseconds(period: 512), 20)
        XCTAssertEqual(BufferAdvice.recommendedMilliseconds(period: 1024), 30)
        XCTAssertEqual(BufferAdvice.recommendedMilliseconds(period: 300), 20, "between two measures: the larger one")
    }

    func testBeyondWhatWasMeasuredTheAdviceGrowsAndSaysItIsAnEstimate() {
        XCTAssertEqual(BufferAdvice.recommendedMilliseconds(period: 2048), 60)
        XCTAssertEqual(BufferAdvice.recommendedMilliseconds(period: 1280), 40)
        XCTAssertTrue(BufferAdvice.isMeasured(period: 1024)); XCTAssertFalse(BufferAdvice.isMeasured(period: 2048))
    }

    func testTheMarginIsJudgedOnTheLastSeconds() {
        XCTAssertEqual(BufferAdvice.assess(history: [5, 5, 5]), .unknown, "too few lines")
        XCTAssertEqual(BufferAdvice.assess(history: Array(repeating: 4.0, count: 20)), .comfortable)
        XCTAssertEqual(BufferAdvice.assess(history: Array(repeating: 4.0, count: 19) + [0.6]), .tight)
        XCTAssertEqual(BufferAdvice.assess(history: Array(repeating: 4.0, count: 19) + [-2]), .dropping)
        XCTAssertEqual(BufferAdvice.assess(history: [-3] + Array(repeating: 4.0, count: 60)), .comfortable, "an old drop is out of the window")
    }

    func testAnAdviceIsOnlyMadeWhenItWouldHelp() {
        XCTAssertEqual(BufferAdvice.suggestion(period: 1024, buffer: 10, assessment: .dropping), 30)
        XCTAssertEqual(BufferAdvice.suggestion(period: 1024, buffer: 10, assessment: .tight), 30)
        XCTAssertNil(BufferAdvice.suggestion(period: 1024, buffer: 10, assessment: .comfortable))
        XCTAssertNil(BufferAdvice.suggestion(period: 1024, buffer: 30, assessment: .dropping), "the buffer is already what is advised")
        XCTAssertNil(BufferAdvice.suggestion(period: nil, buffer: 10, assessment: .dropping))
        XCTAssertNil(BufferAdvice.suggestion(period: 1024, buffer: 10, assessment: .unknown))
    }

    // MARK: Settings

    func testTheSettingsAreRememberedAndTheFirstTimeGivesDefaults() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "zita-settings-\(UUID().uuidString)"))
        let store = BridgeSettingsStore(defaults: defaults)
        XCTAssertFalse(store.hasSavedSettings)
        XCTAssertEqual(store.load(), StoredBridgeSettings())
        var s = StoredBridgeSettings()
        s.receive.address = "10.10.10.1"; s.receive.bufferMilliseconds = 30; s.send.channels = 8; s.sendArmed = false
        store.save(s)
        XCTAssertTrue(store.hasSavedSettings)
        XCTAssertEqual(BridgeSettingsStore(defaults: defaults).load(), s)
    }

    func testSettingsThatCannotBeReadAreReplacedByDefaults() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "zita-settings-\(UUID().uuidString)"))
        defaults.set(Data("not json".utf8), forKey: BridgeSettingsStore.defaultsKey)
        XCTAssertEqual(BridgeSettingsStore(defaults: defaults).load(), StoredBridgeSettings())
    }
}
