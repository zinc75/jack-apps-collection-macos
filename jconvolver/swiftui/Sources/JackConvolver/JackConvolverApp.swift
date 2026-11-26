// SPDX-License-Identifier: GPL-3.0-or-later

import AppearanceKit
import UpdateKit
import SessionKit
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

    /// The click on the icon of the Dock while no window is seen: the window of the one session that has none, or the list of them when there are several
    /// (what is already open stays as it is, and with no session at all it is the usual new window).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Self.hub?.sessionHub.handleReopen(hasVisibleWindows: flag) ?? true
    }

    /// The application stays while an engine goes on without its window (it is in the menu bar).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { Self.hub?.sessionHub.shouldTerminateAfterLastWindowClosed ?? true }
    func applicationDidFinishLaunching(_ notification: Notification) { Self.appearance?.applyAppearance() }
    func applicationWillTerminate(_ notification: Notification) { Self.hub?.shutdown() }
    /// Quitting asks every session (the changes that are not saved, the engine that runs); one that says no keeps the application open.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Self.hub?.sessionHub.terminateReply() ?? .terminateNow
    }
}

@main
struct JackConvolverApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var hub: AppHub
    @State private var appearance: AppearanceSettings
    /// The search for a newer release, and its installation from the Installer.
    @State private var updates: UpdateController

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

        // An installation would cut the convolution: it waits for the sessions to be stopped.
        let updates = UpdateController(
            configuration: UpdateConfiguration(
                appName: "Jack Convolver",
                repository: "zinc75/jack-apps-collection-macos",
                tagPrefix: "jconvolver-v",
                isBusy: { hub.sessionHub.anyRunning }),
            appearance: appearance)
        _updates = State(initialValue: updates)
        updates.startAutomaticChecks()
    }

    var body: some Scene {
        // One window for each session: the number of a session is the value of its window.
        WindowGroup(for: UUID.self, content: { $id in
            SessionWindowHost(hub: hub.sessionHub, id: id) { session in
                ContentView()
                    .environment(session)
                    .environment(appearance)
                    .appAccent(appearance)
                    .focusedSceneValue(\.session, session)
                    .frame(minWidth: 1070, minHeight: 830)
            }
        }, defaultValue: { hub.sessionHub.defaultWindowID() })
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
            // After the "About" group that the menus of the collection replace, so that it stays.
            UpdateCommands(controller: updates)
        }

        // The list of the sessions in a window, for the click on the Dock when several have none (the same list as the panel of the menu bar).
        Window(hub.sessionHub.configuration.sessionsWindowTitle, id: SessionIdentifiers.sessionsWindow) {
            SessionsWindowView(hub: hub.sessionHub, openAction: { hub.openInNewSession() }, accessory: AnyView(JackLoadChip(hub: hub)))
                .environment(appearance)
                .appAccent(appearance)
                .containerBackground(Color.windowFill, for: .window)
        }
        .defaultSize(width: 700, height: 520)
        // In the middle of the screen, not at its top.
        .defaultPosition(.center)
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        // The icon of the menu bar: there only while something is to be reached from it, and filled while an engine runs.
        MenuBarExtra(isInserted: Binding(get: { hub.sessionHub.showsMenuBarIcon }, set: { _ in })) {
            SessionMenuPanel(hub: hub.sessionHub)
                .environment(appearance)
                .appAccent(appearance)
        } label: {
            Image(systemName: hub.sessionHub.anyRunning ? "waveform.circle.fill" : "waveform.circle")
        }
        // A panel and not a menu: a row has buttons, not a submenu.
        .menuBarExtraStyle(.window)
    }
}

/// The load of JACK, shown by the list of the sessions while an engine runs.
private struct JackLoadChip: View {
    let hub: AppHub

    var body: some View {
        if let load = hub.jack.cpuLoad, hub.sessionHub.anyRunning {
            Chip(text: Text("JACK \(Int(load.rounded())) %"), kind: load >= 90 ? .bad : load >= 70 ? .warn : .plain, symbol: "waveform.path.ecg")
        }
    }
}
