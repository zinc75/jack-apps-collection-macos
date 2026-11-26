// SPDX-License-Identifier: GPL-3.0-or-later

import AppearanceKit
import UpdateKit
import SessionKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var hub: AppHub?
    static var appearance: AppearanceSettings?

    /// The click on the icon of the Dock while no window is seen: the window of the one session that has none, or the list of them when there are several
    /// (what is already open stays as it is, and with no session at all it is the usual new window).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Self.hub?.sessionHub.handleReopen(hasVisibleWindows: flag) ?? true
    }

    /// The application stays while a file goes on playing without its window (it is in the menu bar).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { Self.hub?.sessionHub.shouldTerminateAfterLastWindowClosed ?? true }
    func applicationDidFinishLaunching(_ notification: Notification) { Self.appearance?.applyAppearance() }
    func applicationWillTerminate(_ notification: Notification) { Self.hub?.shutdown() }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Self.hub?.sessionHub.terminateReply() ?? .terminateNow
    }

    /// A file dropped on the icon, or opened from the Finder: it goes to a session (the person is asked which one when it is not obvious).
    func application(_ application: NSApplication, open urls: [URL]) {
        Self.hub?.openFromOutside(urls)
    }
}

@main
struct JackPlayApp: App {
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
        keeps = !env.keys.contains { $0.hasPrefix("JACKPLAY_") }
        #endif
        let hub = AppHub(defaults: keeps ? .standard : nil)
        _hub = State(initialValue: hub)
        AppDelegate.hub = hub

        var defaults = UserDefaults.standard
        #if DEBUG
        if env["JACKPLAY_APPEARANCE"] != nil || env["JACKPLAY_ACCENT"] != nil {
            defaults = UserDefaults(suiteName: "jackplay.debug.\(UUID().uuidString)") ?? defaults
            if let v = env["JACKPLAY_APPEARANCE"] { defaults.set(v, forKey: AppearanceSettings.modeKey) }
            if let v = env["JACKPLAY_ACCENT"] { defaults.set(v, forKey: AppearanceSettings.accentKey) }
        }
        #endif
        // The accent of the application is a turquoise green.
        let appearance = AppearanceSettings(appAccent: .green, appColor: Color(red: 0.067, green: 0.639, blue: 0.576), defaults: defaults)
        AppDelegate.appearance = appearance
        _appearance = State(initialValue: appearance)

        // An installation would cut a playback: it waits for the sessions to be stopped.
        let updates = UpdateController(
            configuration: UpdateConfiguration(
                appName: "Jack Play",
                repository: "zinc75/jack-apps-collection-macos",
                tagPrefix: "jack_play-v",
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
                    .frame(minWidth: 900, minHeight: 640)
            }
        }, defaultValue: { hub.sessionHub.defaultWindowID() })
        .defaultSize(width: 1080, height: 740)
        .windowResizability(.contentMinSize)
        // The windows are not brought back at the next launch: a session is something the person starts.
        .restorationBehavior(.disabled)
        .commands { PlayCommands(hub: hub) }
        .commands {
            CollectionMenus(
                about: AboutInfo(
                    name: "Jack Play",
                    // The version shown is the one of the program, then "macOS Edition"; the build number is not shown.
                    version: "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") macOS Edition",
                    summary: String(localized: "Interface non officielle de jack_play (rju-play de Rohan Drape)."),
                    lines: [String(localized: "Portage macOS et interface : Éric Bavu."), String(localized: "Licence GPL, version 3.")],
                    copyright: "© 2026 Éric Bavu",
                    sourceURL: URL(string: "https://github.com/zinc75/jack-apps-collection-macos"),
                    supportURL: URL(string: "https://buymeacoffee.com/zinc75"),
                    licenseFile: "jack_play-COPYING.txt",
                    licenseURL: URL(string: "https://www.gnu.org/licenses/gpl-3.0.html")),
                appearance: appearance,
                documentationTitle: String(localized: "Documentation Jack Play"),
                documentationURL: URL(string: "https://github.com/zinc75/jack-apps-collection-macos/tree/main/jack_play")!)
            // After the "About" group that the menus of the collection replace, so that it stays.
            UpdateCommands(controller: updates)
        }

        // The list of the sessions in a window, for the click on the Dock when several have none (the same list as the panel of the menu bar).
        Window(hub.sessionHub.configuration.sessionsWindowTitle, id: SessionIdentifiers.sessionsWindow) {
            SessionsWindowView(hub: hub.sessionHub)
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

        // The icon of the menu bar: there only while something is to be reached from it, and filled while a file plays.
        MenuBarExtra(isInserted: Binding(get: { hub.sessionHub.showsMenuBarIcon }, set: { _ in })) {
            SessionMenuPanel(hub: hub.sessionHub)
                .environment(appearance)
                .appAccent(appearance)
        } label: {
            Image(systemName: hub.sessionHub.anyRunning ? "play.circle.fill" : "play.circle")
        }
        // A panel and not a menu: a row has buttons, not a submenu.
        .menuBarExtraStyle(.window)
    }
}
