# SessionKit

The sessions of a macOS application, in windows, in the menu bar and in the Dock. A session is what a tool does in one window: a configuration with its engine, a recording, a player. The package knows nothing about any tool: a tool describes its sessions with `HostedSession` and the kit does the rest. macOS 15, MIT licence.

## What it does

`SessionHub` keeps the sessions and what is seen of them. One window for each, found again by the number of the session. A window can be closed while what the session runs goes on: the session stays without a window, the application stays in the Dock while something runs (with the number of sessions that run on its icon, if the tool wants it), and an icon of the menu bar appears while there is something to reach from it. A click on the icon of the Dock gives the window of the one session that has none, or the list of the sessions when there are several.

`SessionWindowHost` is the content of the window of a session. It tells the hub how to open another window and asks the session before the window closes (`WindowCloseGuard`). `SessionMenuPanel` is the panel of the icon of the menu bar, with one row for each session and buttons to bring its window back, to start or stop it and to close it. `SessionsWindowView` is the same list as a window, with a card for each session.

## What a tool gives

A session is a `HostedSession`: a number, a `card` (what the lists show of it: name, a line of detail, its state, badges, gauges and notes), whether something runs, and the few things that depend on the tool: what closing its window leads to (`decisionForClosingWindow`: keep running, stop, cancel), whether quitting is allowed, how to stop it. The questions asked to the person, and their words, stay in the tool.

The tool declares three scenes with the kit: a `WindowGroup(for: UUID.self)` whose content is a `SessionWindowHost`, a `Window` with the id `SessionIdentifiers.sessionsWindow` for the list, and a `MenuBarExtra` with the panel. The delegate of the application asks the hub three things: `handleReopen`, `shouldTerminateAfterLastWindowClosed` and `terminateReply`.

## Tests

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

## Licence

MIT, see `LICENSE`.
