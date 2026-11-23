// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The numbers that a filter field says: "3", "1,3", "2-4", "1 3-5". Used to choose inputs and outputs from a list.
public enum NumberFilter {
    /// nil when it says none (the field is empty, or what is typed is not a number yet): the list is then not emptied while a number is being typed.
    public static func numbers(_ text: String) -> Set<Int>? {
        var out = Set<Int>()
        for part in text.split(whereSeparator: { $0 == "," || $0 == " " || $0 == ";" }) {
            let bounds = part.split(separator: "-").compactMap { Int($0) }
            if bounds.count == 1 { out.insert(bounds[0]) }
            else if bounds.count == 2, bounds[0] <= bounds[1], bounds[1] - bounds[0] < 4096 { out.formUnion(bounds[0]...bounds[1]) }
        }
        return out.isEmpty ? nil : out
    }
}
