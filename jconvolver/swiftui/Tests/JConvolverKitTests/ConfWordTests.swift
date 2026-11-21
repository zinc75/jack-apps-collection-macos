// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import JConvolverKit

final class ConfWordTests: XCTestCase {
    private func read(_ text: String) -> (String, String)? {
        ConfWord.read(Substring(text)).map { ($0.word, String($0.rest)) }
    }

    func testPlainWordEndsAtBlank() {
        let r = read("  hello world")
        XCTAssertEqual(r?.0, "hello")
        XCTAssertEqual(r?.1, " world")
    }

    func testTabIsABlank() {
        XCTAssertEqual(read("a\tb")?.0, "a")
    }

    func testWordEndsAtTheEndOfTheText() {
        let r = read("/Users/eric/ir.wav")
        XCTAssertEqual(r?.0, "/Users/eric/ir.wav")
        XCTAssertEqual(r?.1, "")
    }

    func testDoubleQuotesHoldBlanks() {
        let r = read("\"my file.wav\" 3")
        XCTAssertEqual(r?.0, "my file.wav")
        XCTAssertEqual(r?.1, " 3")
    }

    func testSingleQuotesTakeBackslashesAsTheyAre() {
        XCTAssertEqual(read(#"'a\b'"#)?.0, #"a\b"#)
    }

    func testBackslashMakesTheNextCharacterLiteral() {
        XCTAssertEqual(read(#"a\ b c"#)?.0, "a b")
        XCTAssertEqual(read(#""say \"hi\"""#)?.0, #"say "hi""#)
    }

    func testEmptyQuotesAreAnEmptyWord() {
        let r = read("\"\" x")
        XCTAssertEqual(r?.0, "")
        XCTAssertEqual(r?.1, " x")
    }

    func testWhatSstringRefuses() {
        XCTAssertNil(read(""))
        XCTAssertNil(read("   "))
        XCTAssertNil(read("\"open"))          // a quote that is never closed
        XCTAssertNil(read("a\"b\""))           // a quote in the middle of a word
        XCTAssertNil(read("\"a'b'\""))         // a quote of the other kind inside quotes
        XCTAssertNil(read("a\\"))              // a backslash at the very end
    }

    func testFormatKeepsSafeWordsAsTheyAre() {
        XCTAssertEqual(ConfWord.format("In.L"), "In.L")
        XCTAssertEqual(ConfWord.format("/Users/eric/ir.wav"), "/Users/eric/ir.wav")
        XCTAssertEqual(ConfWord.format("system:capture_1"), "system:capture_1")
    }

    func testFormatQuotesWhatNeedsIt() {
        XCTAssertEqual(ConfWord.format("my file.wav"), "\"my file.wav\"")
        XCTAssertEqual(ConfWord.format(""), "\"\"")
        XCTAssertEqual(ConfWord.format(#"say "hi""#), #""say \"hi\"""#)
        XCTAssertEqual(ConfWord.format("it's"), #""it\'s""#)
    }

    func testWhatIsWrittenIsReadBack() {
        for word in ["In.L", "my file.wav", "", #"a"b\c"#, "it's", "  spaced  ", "é à ü", "/Volumes/IR 2025/room (A).wav"] {
            let written = ConfWord.format(word)
            XCTAssertEqual(read(written + " rest")?.0, word, "«\(word)» written \(written)")
        }
    }
}
