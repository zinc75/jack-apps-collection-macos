// SPDX-License-Identifier: MIT

import AppKit
import AppearanceKit
import MatrixKit
import SwiftUI

/// The window of a session: the content that the tool gives, with what the kit needs of a window. It tells the hub how to open another window, and which
/// window is the one of this session, and it asks the session before the window closes.
public struct SessionWindowHost<S: HostedSession, Content: View>: View {
    let hub: SessionHub<S>
    let content: (S) -> Content
    @State private var session: S
    @Environment(\.openWindow) private var openWindow

    public init(hub: SessionHub<S>, id: UUID, @ViewBuilder content: @escaping (S) -> Content) {
        self.hub = hub
        self.content = content
        // The session of this window: made the first time, found again after.
        _session = State(initialValue: hub.session(for: id))
    }

    public var body: some View {
        content(session)
            .background(WindowCloseGuard(hub: hub, session: session))
            .onAppear {
                hub.openWindowAction = { openWindow(value: $0) }
                hub.openSessionsAction = { openWindow(id: SessionIdentifiers.sessionsWindow) }
                hub.watchWindows()
            }
    }
}

public enum SessionIdentifiers {
    /// The identifier of the window that lists the sessions.
    public static let sessionsWindow = "sessions"
}

/// Asks before the window closes, as the system does for a document, and tells the hub when it is gone. The delegate of the window stays the one SwiftUI
/// gave it: this one answers `windowShouldClose` and `windowWillClose` and passes everything else on.
struct WindowCloseGuard<S: HostedSession>: NSViewRepresentable {
    let hub: SessionHub<S>
    let session: S

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { Anchor(coordinator: context.coordinator, hub: hub, session: session) }
    func updateNSView(_ view: NSView, context: Context) {}

    final class Coordinator { var proxy: Proxy? }

    @MainActor final class Proxy: NSObject, NSWindowDelegate {
        weak var original: NSWindowDelegate?
        let shouldClose: @MainActor () -> Bool
        let didClose: @MainActor () -> Void

        init(shouldClose: @escaping @MainActor () -> Bool, didClose: @escaping @MainActor () -> Void) {
            self.shouldClose = shouldClose
            self.didClose = didClose
        }

        override func responds(to selector: Selector!) -> Bool { super.responds(to: selector) || (original?.responds(to: selector) ?? false) }
        override func forwardingTarget(for selector: Selector!) -> Any? {
            if original?.responds(to: selector) == true { return original }
            return super.forwardingTarget(for: selector)
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            guard shouldClose() else { return false }
            return original?.windowShouldClose?(sender) ?? true
        }

        func windowWillClose(_ notification: Notification) {
            didClose()
            original?.windowWillClose?(notification)
        }
    }

    private final class Anchor: NSView {
        let coordinator: Coordinator
        let hub: SessionHub<S>
        let session: S

        init(coordinator: Coordinator, hub: SessionHub<S>, session: S) {
            self.coordinator = coordinator
            self.hub = hub
            self.session = session
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError() }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, coordinator.proxy == nil else { return }
            let hub = hub, session = session
            hub.attach(window, to: session)
            let proxy = Proxy(shouldClose: { hub.windowShouldClose(session) }, didClose: { hub.windowClosed(session) })
            proxy.original = window.delegate
            coordinator.proxy = proxy
            window.delegate = proxy
        }
    }
}

// MARK: What the lists show

private func summary<S: HostedSession>(_ hub: SessionHub<S>, sessions: Int, running: Int) -> String {
    let s = sessions == 1 ? String(localized: "1 session") : String(localized: "\(sessions) sessions")
    let noun = running == 1 ? hub.configuration.runningNoun : hub.configuration.runningNounPlural
    let r = running == 0 ? String(localized: "aucun en cours d'exécution") : String(localized: "\(running) \(noun) en cours d'exécution")
    return s + ", " + r
}

/// A capsule button of the lists of sessions; the one that is `prominent` takes the accent.
struct SessionButton: View {
    let title: LocalizedStringKey
    var symbol: String?
    var prominent = false
    let action: () -> Void
    @Environment(\.appAccentColor) private var accent
    @Environment(\.isEnabled) private var isEnabled

    init(_ title: LocalizedStringKey, symbol: String? = nil, prominent: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.prominent = prominent
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.system(size: 12, weight: .semibold)) }
                Text(title).font(.system(size: 13, weight: prominent ? .semibold : .regular))
            }
            .padding(.horizontal, 13).frame(height: 30)
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .background(prominent ? accent : Color.primary.opacity(0.09), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(prominent ? 0 : 0.14), lineWidth: 0.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.4)
    }
}

/// A round button with a symbol only.
struct SessionGlyph: View {
    let symbol: String
    let help: String
    var enabled = true
    let action: () -> Void

    init(_ symbol: String, help: String, enabled: Bool = true, action: @escaping () -> Void) {
        self.symbol = symbol
        self.help = help
        self.enabled = enabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(Color.primary.opacity(0.09), in: Circle())
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .help(help)
    }
}

private struct SessionChip: View {
    let badge: SessionBadge

    var body: some View {
        HStack(spacing: 5) {
            if let symbol = badge.symbol { Image(systemName: symbol).font(.system(size: 10, weight: .semibold)) }
            Text(verbatim: badge.text)
        }
        .font(.caption).fontWeight(.medium).foregroundStyle(.secondary)
        .padding(.horizontal, 9).frame(height: 22)
        .background(Color.primary.opacity(0.07), in: Capsule())
    }
}

private struct SessionGaugeView: View {
    let gauge: SessionGauge
    @Environment(\.appAccentColor) private var accent

    var body: some View {
        let tint: Color = gauge.level == .alert ? .red : gauge.level == .warning ? .orange : accent
        HStack(spacing: 6) {
            Text(verbatim: gauge.label).foregroundStyle(.secondary)
            ProgressView(value: min(1, max(0, gauge.value))).progressViewStyle(.linear).frame(width: 54).tint(tint)
            Text(verbatim: gauge.text).monospacedDigit()
        }
        .font(.caption)
    }
}

/// A session in the window of the sessions.
private struct SessionCardView<S: HostedSession>: View {
    let hub: SessionHub<S>
    let session: S
    @Environment(\.appAccentColor) private var accent

    var body: some View {
        let card = session.card
        let running = card.state == .active, failed = card.state == .failed
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(running ? Color.green.opacity(0.18) : failed ? Color.red.opacity(0.18) : Color.primary.opacity(0.08))
                Image(systemName: running ? "play.fill" : failed ? "exclamationmark" : "gearshape")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(running ? Color.green : failed ? Color.red : Color.secondary)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(verbatim: card.title).font(.system(size: 14, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                    if card.isModified { Text("Modifié").font(.caption).foregroundStyle(.orange) }
                }
                Text(verbatim: card.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 14) {
                    ForEach(card.badges) { SessionChip(badge: $0) }
                    if running {
                        ForEach(card.gauges) { SessionGaugeView(gauge: $0) }
                    } else {
                        Text(verbatim: card.stateText).font(.caption).foregroundStyle(failed ? Color.red : Color.secondary)
                    }
                    ForEach(card.notes) { Text(verbatim: $0.text).font(.caption).monospacedDigit().foregroundStyle($0.isAlert ? Color.red : Color.secondary) }
                }
                .padding(.top, 3)
            }
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                SessionButton("Afficher", symbol: "macwindow", prominent: running) { hub.showWindow(of: session) }
                if session.canStartFromList {
                    SessionGlyph(running ? "stop.fill" : "play.fill", help: running ? String(localized: "Arrêter") : String(localized: "Lancer"),
                                 enabled: session.canToggle) { session.toggle() }
                }
                if hub.isWindowHidden(session), !running {
                    SessionGlyph("xmark", help: String(localized: "Fermer la session")) { hub.discard(session) }
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .blockBackground(cornerRadius: 14)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(accent.opacity(running ? 0.55 : 0), lineWidth: 1))
    }
}

/// The window that lists the sessions, what the click on the Dock leads to when several of them have no window: a card for each, with what it does and the
/// buttons to bring its window back, to start or stop it, or to close it.
public struct SessionsWindowView<S: HostedSession>: View {
    let hub: SessionHub<S>
    let openAction: (() -> Void)?
    let accessory: AnyView?
    @Environment(\.openWindow) private var openWindow

    /// - Parameters:
    ///   - openAction: what the button "Ouvrir…" does (the tool opens its own kind of file in a session of its own); nil for no such button.
    ///   - accessory: something the tool shows at the right of the title (the load of JACK).
    public init(hub: SessionHub<S>, openAction: (() -> Void)? = nil, accessory: AnyView? = nil) {
        self.hub = hub
        self.openAction = openAction
        self.accessory = accessory
    }

    public var body: some View {
        // The scene knows how to open a window, also when none is open.
        let _ = { hub.openWindowAction = { openWindow(value: $0) }; hub.openSessionsAction = { openWindow(id: SessionIdentifiers.sessionsWindow) } }()
        let sessions = hub.shownSessions
        let running = sessions.filter(\.isActive).count
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sessions").font(.title2).fontWeight(.semibold)
                    Text(verbatim: summary(hub, sessions: sessions.count, running: running)).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if let accessory { accessory }
            }
            .padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 12)

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(sessions, id: \.id) { SessionCardView(hub: hub, session: $0) }
                }
                .padding(.horizontal, 22).padding(.vertical, 4)
            }

            HStack(spacing: 8) {
                SessionButton("Nouvelle session", symbol: "plus") { hub.newSession() }
                if let openAction { SessionButton("Ouvrir…", symbol: "folder", action: openAction) }
                SessionButton("Tout afficher", symbol: "macwindow.on.rectangle") { hub.showAllWindows() }.disabled(sessions.isEmpty)
                SessionButton("Tout fermer", symbol: "xmark.rectangle") { hub.closeAll() }.disabled(sessions.isEmpty)
                Spacer()
                SessionButton("Quitter") { NSApp.terminate(nil) }
            }
            .padding(.horizontal, 22).padding(.vertical, 14)
            .overlay(alignment: .top) { Divider() }
        }
        .frame(minWidth: 640, minHeight: 360)
    }
}

/// The panel of the icon in the menu bar: one row for each session, with what it is doing and the buttons to bring its window back, to start or stop it,
/// or to close it, and quitting at the bottom.
public struct SessionMenuPanel<S: HostedSession>: View {
    let hub: SessionHub<S>
    @Environment(\.openWindow) private var openWindow

    public init(hub: SessionHub<S>) { self.hub = hub }

    public var body: some View {
        // The scene of the icon knows how to open a window, also when none is open.
        let _ = { hub.openWindowAction = { openWindow(value: $0) }; hub.openSessionsAction = { openWindow(id: SessionIdentifiers.sessionsWindow) } }()
        VStack(alignment: .leading, spacing: 2) {
            ForEach(hub.shownSessions, id: \.id) { SessionRowView(hub: hub, session: $0) }
            Divider().padding(.vertical, 4)
            if !hub.shownSessions.isEmpty {
                panelButton("Tout afficher", symbol: "macwindow.on.rectangle") { hub.showAllWindows() }
                panelButton("Tout fermer", symbol: "xmark.rectangle") { hub.closeAll() }
            }
            panelButton("Nouvelle session", symbol: "plus.circle") { hub.newSession() }
            Button { NSApp.terminate(nil) } label: {
                HStack {
                    Text(verbatim: String(localized: "Quitter") + " " + hub.configuration.toolName)
                    Spacer()
                    Text("⌘Q").foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q")
            .padding(.horizontal, 10).padding(.vertical, 5)
        }
        .padding(8)
        .frame(width: 340)
    }

    private func panelButton(_ title: LocalizedStringKey, symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: symbol)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10).padding(.vertical, 5)
    }
}

/// A session in the panel of the menu bar.
private struct SessionRowView<S: HostedSession>: View {
    let hub: SessionHub<S>
    let session: S
    @State private var hovered = false

    var body: some View {
        let card = session.card
        let running = card.state == .active
        HStack(spacing: 10) {
            Circle().fill(running ? Color.green : card.state == .failed ? Color.red : Color.secondary.opacity(0.4)).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: card.title).lineLimit(1).truncationMode(.middle)
                Text(verbatim: line(card)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            glyph("macwindow", help: String(localized: "Afficher la fenêtre")) { hub.showWindow(of: session) }
            if session.canStartFromList {
                glyph(running ? "stop.fill" : "play.fill", help: running ? String(localized: "Arrêter") : String(localized: "Lancer"), enabled: session.canToggle) { session.toggle() }
            }
            if hub.isWindowHidden(session), !running {
                glyph("xmark", help: String(localized: "Fermer la session")) { hub.discard(session) }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.primary.opacity(hovered ? 0.08 : 0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { hovered = $0 }
    }

    /// What the session is doing: its state, and while it runs the first badge (the JACK client, the time of a recording).
    private func line(_ card: SessionCard) -> String {
        guard card.state == .active, let badge = card.badges.first else { return card.stateText }
        return card.stateText + " · " + badge.text
    }

    private func glyph(_ name: String, help: String, enabled: Bool = true, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).font(.system(size: 13, weight: .semibold))
                .frame(width: 26, height: 24)
                .background(Color.primary.opacity(0.08), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .help(help)
    }
}
