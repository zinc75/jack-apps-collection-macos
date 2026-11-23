// SPDX-License-Identifier: MIT

import AppKit
import SwiftUI

/// The colours the traces of a plot get by default after the accent: the qualitative sequence of Plotly (whose purple is the accent itself), in
/// an order for each appearance, starting with the ones that read best on its background: bright and distinct on a dark one, strong on a light
/// one, the pale ones last.
enum PlotTraceColors {
    private static let red = 0xEF553B, green = 0x00CC96, orange = 0xFFA15A, cyan = 0x19D3F3, pink = 0xFF6692
    private static let lightGreen = 0xB6E880, magenta = 0xFF97FF, yellow = 0xFECB52, indigo = 0x636EFA

    /// On a dark background the bright colours stand out; the indigo is the one that sinks into it.
    static let dark = [green, orange, cyan, pink, yellow, red, lightGreen, magenta, indigo]
    /// On a light background the strong colours read; the yellow, the light green and the magenta are pale.
    static let light = [red, green, orange, indigo, pink, cyan, lightGreen, magenta, yellow]

    static func color(_ hex: Int) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }

    /// The colour at a place of the sequence that follows the appearance: what a channel keeps as its colour, and that the person can choose from
    /// a row of swatches, whichever the appearance is when it is drawn.
    static let adaptive: [Color] = (0..<dark.count).map { k in
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let hex = isDark ? dark[k] : light[k]
            return NSColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}
