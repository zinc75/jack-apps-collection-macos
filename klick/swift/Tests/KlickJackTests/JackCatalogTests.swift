// SPDX-License-Identifier: GPL-2.0-or-later
// Licence of the program this interface drives (klick).
import XCTest

/// The string catalog of the JACK module (`Resources/Localizable.xcstrings`): French is the source language, the keys are the French
/// texts of the sources, and every one is translated into English, German, Italian and Spanish.
final class JackCatalogTests: XCTestCase {
    static let catalogURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Resources/Localizable.xcstrings")
    static let languages = ["en", "de", "it", "es"]

    private func catalog() throws -> [String: [String: String]] {
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: Self.catalogURL)) as? [String: Any])
        XCTAssertEqual(root["sourceLanguage"] as? String, "fr")
        let strings = try XCTUnwrap(root["strings"] as? [String: [String: Any]])
        return strings.mapValues { entry in
            let localizations = entry["localizations"] as? [String: [String: Any]] ?? [:]
            return localizations.compactMapValues { ($0["stringUnit"] as? [String: Any])?["value"] as? String }
        }
    }

    func testEveryTextIsTranslatedIntoEveryLanguage() throws {
        let strings = try catalog()
        XCTAssertGreaterThan(strings.count, 10)
        for (key, values) in strings {
            for language in Self.languages {
                XCTAssertFalse((values[language] ?? "").isEmpty, "\(language) is missing for “\(key)”")
            }
        }
    }

    /// Every French text of the sources is in the catalog.
    func testTheTextsOfTheSourcesAreInTheCatalog() throws {
        let strings = try catalog()
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/KlickJack")
        let files = try FileManager.default.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil).filter { $0.pathExtension == "swift" }
        let regex = try NSRegularExpression(pattern: #"(?:Text|String\(localized:|GroupTitle|OutputRow\(title:|detail: Text)\(?\s*"([^"\\]*(?:\\.[^"\\]*)*)""#)
        // Texts that are the same in every language, or that a catalog of the core holds: not repeated here.
        let elsewhere: Set<String> = ["JACK", "Fréquence d'échantillonnage", "Latence annoncée", "Tampon", "Réglages de la sortie…", "%lld échantillons"]
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                let key = String(text[Range(match.range(at: 1), in: text)!])
                if key.isEmpty || key.contains("\\(") || elsewhere.contains(key) { continue }
                XCTAssertNotNil(strings[key], "“\(key)” (\(file.lastPathComponent)) is not in the catalog")
            }
        }
    }
}
