// SPDX-License-Identifier: GPL-2.0-or-later

import SwiftUI
import MatrixKit
import JackCaptureKit
import AppearanceKit
import SessionKit

/// Removes the menus that the system adds by itself and that have nothing left in them (Format, once its commands are gone),
/// and holds back the quitting while a file is being written.
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var sessions: CaptureSessions?
    /// The look chosen by the user; given by the application before the first window, applied at launch.
    static var appearance: AppearanceSettings?
    private var pending = false

    /// The click on the icon of the Dock while no window is seen: the window of the one session that has none, or the list of them when there are several.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Self.sessions?.handleReopen(hasVisibleWindows: flag) ?? true
    }

    /// The application stays while a recording goes on without its window (it is in the menu bar).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { Self.sessions?.shouldTerminateAfterLastWindowClosed ?? true }

    /// Quitting asks every session, then stops what is written and waits for jack_capture to close the file: it would otherwise be cut (its output pipes
    /// close with the application, and it would die writing to them).
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Self.sessions?.terminateReply() ?? .terminateNow
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.appearance?.applyAppearance()
        prune()
        NotificationCenter.default.addObserver(forName: NSMenu.didAddItemNotification, object: nil, queue: .main) { [weak self] _ in
            self?.schedule()
        }
    }

    private func schedule() {
        guard !pending else { return }
        pending = true
        DispatchQueue.main.async { [self] in
            pending = false
            prune()
        }
    }

    private func prune() {
        guard let main = NSApp.mainMenu else { return }
        for item in main.items.dropFirst() {
            guard let submenu = item.submenu else { continue }
            if submenu.items.allSatisfy({ $0.isSeparatorItem || $0.isHidden }) { main.removeItem(item) }
        }
    }
}

@main
struct JackCaptureApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// The sessions: one window each. The settings of the last session come back in the first one; a development run that forces settings does not keep them.
    @State private var sessions: CaptureSessions
    @State private var appearance: AppearanceSettings

    private static var keepsSettings: Bool {
        #if DEBUG
        return !ProcessInfo.processInfo.environment.keys.contains { $0.hasPrefix("JACKCAPTURE_AUTO") }
        #else
        return true
        #endif
    }

    init() {
        CollectionMenus.disableSystemMenuAdditions()
        let hub = CaptureHub(defaults: Self.keepsSettings ? .standard : nil)
        let sessions = CaptureSessions(
            configuration: SessionKitConfiguration(toolName: "Jack Capture", showsDockBadge: true, runningNoun: "enregistrement", runningNounPlural: "enregistrements"),
            makeSession: { id in
                let session = RecorderModel(hub: hub, id: id, usesSavedSettings: hub.claimSavedSettings())
                session.notify = { CaptureNotifier.post(title: $0, body: $1) }
                return session
            },
            makeIdleSession: { RecorderModel(hub: hub, usesSavedSettings: false) })
        _sessions = State(initialValue: sessions)
        AppDelegate.sessions = sessions
        #if DEBUG
        if ProcessInfo.processInfo.environment["JACKCAPTURE_FRESH"] != nil { hub.pretendFirstLaunch() }
        #endif

        // The colour of the application is a red a little deeper than the one of the system, so that it is not taken for the red of
        // the record button or of an alert; the look is dark until the user says otherwise.
        var defaults = UserDefaults.standard
        #if DEBUG
        // Development aids: JACKCAPTURE_APPEARANCE=dark|system|light and JACKCAPTURE_ACCENT=app|system|blue|purple|pink|red|orange|green
        // set the look of the run, in a store of their own that is not kept.
        let environment = ProcessInfo.processInfo.environment
        if environment["JACKCAPTURE_APPEARANCE"] != nil || environment["JACKCAPTURE_ACCENT"] != nil {
            defaults = UserDefaults(suiteName: "jackcapture.debug.\(UUID().uuidString)") ?? defaults
            if let value = environment["JACKCAPTURE_APPEARANCE"] { defaults.set(value, forKey: AppearanceSettings.modeKey) }
            if let value = environment["JACKCAPTURE_ACCENT"] { defaults.set(value, forKey: AppearanceSettings.accentKey) }
        }
        #endif
        let appearance = AppearanceSettings(appAccent: .red, appColor: Color(red: 0.90, green: 0.17, blue: 0.24), defaults: defaults)
        AppDelegate.appearance = appearance
        _appearance = State(initialValue: appearance)
    }

    var body: some Scene {
        // One window for each session: the number of a session is the value of its window.
        WindowGroup(for: UUID.self, content: { $id in
            SessionWindowHost(hub: sessions, id: id) { session in
                ContentView()
                    .environment(session)
                    .environment(appearance)
                    .appAccent(appearance)
                    .focusedSceneValue(\.session, session)
                    // The window is never smaller than 940 x 850 (the toolbar adds 52 points to the height below).
                    .frame(minWidth: 940, minHeight: 798)
            }
        }, defaultValue: { sessions.defaultWindowID() })
        .defaultSize(width: 1120, height: 850)
        .windowResizability(.contentMinSize)
        // The windows are not brought back at the next launch: a session is something the person starts.
        .restorationBehavior(.disabled)
        .commands { CaptureCommands(hub: sessions) }
        .commands {
            CollectionMenus(
                about: AboutInfo(
                    name: "Jack Capture",
                    // The version shown is the one of the program, then "macOS Edition"; the build number is not shown.
                    version: "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") macOS Edition",
                    summary: String(localized: "Interface non officielle de jack_capture, de Kjetil Matheussen."),
                    lines: [String(localized: "Portage macOS et interface : Éric Bavu."), String(localized: "Licence GPL, version 2 ou ultérieure.")],
                    copyright: "© 2026 Éric Bavu",
                    sourceURL: URL(string: "https://github.com/zinc75/jack-apps-collection-macos"),
                    supportURL: URL(string: "https://buymeacoffee.com/zinc75"),
                    licenseFile: "jack_capture-COPYING.txt",
                    licenseURL: URL(string: "https://www.gnu.org/licenses/old-licenses/gpl-2.0.html")),
                appearance: appearance,
                documentationTitle: String(localized: "Documentation Jack Capture"),
                documentationURL: URL(string: "https://github.com/zinc75/jack-apps-collection-macos/tree/main/jack_capture")!)
        }

        // The list of the sessions in a window, for the click on the Dock when several have none (the same list as the panel of the menu bar).
        Window(sessions.configuration.sessionsWindowTitle, id: SessionIdentifiers.sessionsWindow) {
            SessionsWindowView(hub: sessions)
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

        // The icon of the menu bar: there only while something is to be reached from it, and filled while a recording goes on.
        MenuBarExtra(isInserted: Binding(get: { sessions.showsMenuBarIcon }, set: { _ in })) {
            SessionMenuPanel(hub: sessions)
                .environment(appearance)
                .appAccent(appearance)
        } label: {
            Image(systemName: sessions.anyRunning ? "record.circle.fill" : "record.circle")
        }
        // A panel and not a menu: a row has buttons, not a submenu.
        .menuBarExtraStyle(.window)
    }
}
