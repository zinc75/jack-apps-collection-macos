import Foundation

/// The counts of xruns and overruns, said with the agreement of the language (French counts 0 and 1 as singular).
enum IncidentText {
    static func xruns(_ n: Int) -> String {
        n < 2 ? String(localized: "\(n) xrun") : String(localized: "\(n) xruns")
    }

    static func overruns(_ n: Int) -> String {
        n < 2 ? String(localized: "\(n) overrun") : String(localized: "\(n) overruns")
    }
}
