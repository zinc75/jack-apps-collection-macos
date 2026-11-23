// SPDX-License-Identifier: GPL-3.0-or-later

import AppearanceKit
import JConvolverKit
import SwiftUI

/// The edit commands act on the text of a field while one is being edited, and on the matrix otherwise: they take the place of the
/// standard items of the menu, which a text field would otherwise use.
@MainActor
func editCommand(_ selector: Selector, _ onMatrix: () -> Void) {
    if NSApp.keyWindow?.firstResponder is NSTextView { NSApp.sendAction(selector, to: nil, from: nil) } else { onMatrix() }
}

/// Undo and redo are for the view that has the focus: a text being edited (the editor of the configuration, a field) undoes what was typed in it
/// and nothing else; elsewhere it is the last change made in the page that is shown, and only that one.
@MainActor
func undoCommand(redo: Bool, _ onConfiguration: () -> Void) {
    if let text = NSApp.keyWindow?.firstResponder as? NSTextView {
        if let manager = text.undoManager { if redo { if manager.canRedo { manager.redo() } } else if manager.canUndo { manager.undo() } }
    } else {
        onConfiguration()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var hub: AppHub?
    static var appearance: AppearanceSettings?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationDidFinishLaunching(_ notification: Notification) { Self.appearance?.applyAppearance() }
    func applicationWillTerminate(_ notification: Notification) { Self.hub?.shutdown() }
    /// Quitting asks about the changes that are not saved, and about the engine that runs (unless closing the window already did).
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let hub = Self.hub else { return .terminateNow }
        // Every session is asked (the changes that are not saved, the engine that runs); one that says no keeps the application open.
        for session in hub.sessions where !session.leavingConfirmed {
            if !session.confirmLeaving(.quit) { return .terminateCancel }
        }
        return .terminateNow
    }
}

@main
struct JackConvolverApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var hub: AppHub
    @State private var appearance: AppearanceSettings

    init() {
        CollectionMenus.disableSystemMenuAdditions()
        let env = ProcessInfo.processInfo.environment
        var keeps = true
        #if DEBUG
        // Debug aids (JACKCONVOLVER_*) must not touch what the person has set up.
        keeps = !env.keys.contains { $0.hasPrefix("JACKCONVOLVER_") }
        #endif
        let hub = AppHub(defaults: keeps ? .standard : nil)
        _hub = State(initialValue: hub)
        AppDelegate.hub = hub

        var defaults = UserDefaults.standard
        #if DEBUG
        if env["JACKCONVOLVER_APPEARANCE"] != nil || env["JACKCONVOLVER_ACCENT"] != nil {
            defaults = UserDefaults(suiteName: "jackconvolver.debug.\(UUID().uuidString)") ?? defaults
            if let v = env["JACKCONVOLVER_APPEARANCE"] { defaults.set(v, forKey: AppearanceSettings.modeKey) }
            if let v = env["JACKCONVOLVER_ACCENT"] { defaults.set(v, forKey: AppearanceSettings.accentKey) }
        }
        #endif
        // The violet of the application, as in the mockup: a little lighter on the dark look (#b07dfa) than on the light one (#9a5bf2),
        // so that it reads on both. A dynamic colour follows the look of the window by itself.
        let violet = Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 0.690, green: 0.490, blue: 0.980, alpha: 1)
                : NSColor(srgbRed: 0.604, green: 0.357, blue: 0.949, alpha: 1)
        })
        let appearance = AppearanceSettings(appAccent: .purple, appColor: violet, defaults: defaults)
        AppDelegate.appearance = appearance
        _appearance = State(initialValue: appearance)
    }

    var body: some Scene {
        // One window for each session: the number of a session is the value of its window.
        WindowGroup(for: UUID.self, content: { $id in
            SessionWindow(hub: hub, id: id, appearance: appearance)
        }, defaultValue: { UUID() })
        .defaultSize(width: 1180, height: 940)
        .windowResizability(.contentMinSize)
        // The windows are not brought back at the next launch: a session is a configuration that the person opens.
        .restorationBehavior(.disabled)
        .commands { SessionCommands(hub: hub) }
        .commands { SelectionCommands(hub: hub) }
        .commands {
            CollectionMenus(
                about: AboutInfo(
                    name: "Jack Convolver",
                    version: "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") macOS Edition",
                    summary: String(localized: "Interface non officielle de jconvolver et fconvolver, de Fons Adriaensen."),
                    lines: [String(localized: "Portage macOS et interface : Éric Bavu."), String(localized: "Licence GPL, version 3.")],
                    copyright: "© 2026 Éric Bavu",
                    sourceURL: URL(string: "https://github.com/zinc75/jack-apps-collection-macos"),
                    supportURL: URL(string: "https://buymeacoffee.com/zinc75"),
                    licenseFile: "jconvolver-COPYING.txt",
                    licenseURL: URL(string: "https://www.gnu.org/licenses/gpl-3.0.html")),
                appearance: appearance,
                documentationTitle: String(localized: "Documentation Jack Convolver"),
                documentationURL: URL(string: "https://github.com/zinc75/jack-apps-collection-macos/tree/main/jconvolver")!)
        }
    }
}
