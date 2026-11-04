// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation

/// What is typed in a number field: kept as text while it is edited (it may be empty on the way to another
/// number), and turned into a number when the field is validated.
public enum IntegerInput {
    /// The digits of what was typed; anything else is dropped.
    public static func digits(_ text: String) -> String { text.filter { $0.isASCII && $0.isNumber } }

    /// The number the text stands for, inside `range`; the current value when the text holds no digit.
    public static func commit(_ text: String, current: Int, range: ClosedRange<Int>?) -> Int {
        guard let typed = Int(digits(text)) else { return current }
        return range.map { min(max(typed, $0.lowerBound), $0.upperBound) } ?? typed
    }
}
