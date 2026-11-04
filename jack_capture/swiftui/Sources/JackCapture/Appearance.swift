// SPDX-License-Identifier: GPL-2.0-or-later

import SwiftUI

/// The look of the application: the one of the system, or light or dark whatever the system says. Dark all the
/// time is how JackMate looks, and people who keep the system in light may want the Jack apps to match.
/// It is kept between two launches and applies to every window, the matrix included.
enum AppearanceChoice: String, CaseIterable {
    case system, light, dark

    static let key = "appearance"

    static var saved: AppearanceChoice {
        UserDefaults.standard.string(forKey: key).flatMap(AppearanceChoice.init(rawValue:)) ?? .system
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    func apply() { NSApp.appearance = nsAppearance }
}

/// A sun or a moon in the toolbar: it shows the look a click goes to. A right click offers the three choices, among
/// them the system's.
struct AppearanceButton: View {
    /// On macOS 26 the button draws the glass disc itself, as it is kept out of the capsule of its neighbours.
    var ownGlass = false
    @AppStorage(AppearanceChoice.key) private var stored = AppearanceChoice.system.rawValue
    @Environment(\.colorScheme) private var scheme

    private var choice: Binding<AppearanceChoice> {
        Binding(get: { AppearanceChoice(rawValue: stored) ?? .system }, set: { stored = $0.rawValue })
    }

    var body: some View {
        Button {
            choice.wrappedValue = scheme == .dark ? .light : .dark
        } label: {
            Image(systemName: scheme == .dark ? "sun.max" : "moon")
                .frame(width: ownGlass ? 30 : nil, height: ownGlass ? 30 : nil)
                .modifier(OwnGlass(enabled: ownGlass))
        }
        .buttonStyle(.plain)
        .help(scheme == .dark ? "Passer en mode clair" : "Passer en mode sombre")
        .accessibilityLabel(scheme == .dark ? "Passer en mode clair" : "Passer en mode sombre")
        .contextMenu {
            Picker("Apparence", selection: choice) {
                Text("Automatique (réglage du système)").tag(AppearanceChoice.system)
                Text("Clair").tag(AppearanceChoice.light)
                Text("Sombre").tag(AppearanceChoice.dark)
            }
            .pickerStyle(.inline)
        }
        .onChange(of: stored) { choice.wrappedValue.apply() }
    }
}

/// A glass disc behind the sun or the moon, where the system does not draw one.
private struct OwnGlass: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled, #available(macOS 26, *) {
            content.glassEffect(.regular.interactive(), in: .circle)
        } else {
            content
        }
    }
}
