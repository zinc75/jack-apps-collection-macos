// SPDX-License-Identifier: GPL-2.0-or-later

/// The pages of the window, chosen in the sidebar: the recording, then the sections of the settings.
public enum MainView: String, CaseIterable, Sendable {
    case recording
    case channels
    case file
    case startStop
    case advanced
    case display
}

/// Where the recorder is in its journey: configuration, then armed or recording, then done.
public enum RecorderPhase: Sendable, Equatable {
    case configuration
    /// Waiting for the transport, for freewheeling, or for the red button (timemachine).
    case armed
    case recording
    /// jack_capture is flushing its buffer to the disk.
    case stopping
    case done

    /// The configuration is read-only from the moment a recording is armed until it is closed.
    public var isLocked: Bool {
        switch self {
        case .armed, .recording, .stopping: return true
        case .configuration, .done: return false
        }
    }

    /// The big round button shows the stop symbol while something is running.
    public var showsStopSymbol: Bool { isLocked }
}
