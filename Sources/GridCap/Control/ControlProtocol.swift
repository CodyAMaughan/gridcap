import Foundation

// MARK: - Control Command

enum ControlCommand: String, Codable {
    case stop
    case pause
    case resume
    case status
    case addWindow = "add_window"
    case removeWindow = "remove_window"
}

// MARK: - Control Request

struct ControlRequest: Codable {
    let command: ControlCommand
    let window_id: UInt32?

    init(command: ControlCommand, window_id: UInt32? = nil) {
        self.command = command
        self.window_id = window_id
    }
}

// MARK: - Session State

enum SessionState: String, Codable {
    case recording
    case paused
    case stopping
    case stopped
}

// MARK: - Recorder Status

struct RecorderStatus: Codable {
    let window_id: UInt32
    let file: String
    let frame_count: Int64
    let duration_seconds: Double
    let file_size_bytes: Int64
    let is_paused: Bool
}

// MARK: - Control Response

struct ControlResponse: Codable {
    let status: String
    let message: String
    let session_state: SessionState?
    let recorders: [RecorderStatus]?

    init(status: String, message: String, session_state: SessionState? = nil, recorders: [RecorderStatus]? = nil) {
        self.status = status
        self.message = message
        self.session_state = session_state
        self.recorders = recorders
    }

    static func ok(_ message: String, state: SessionState? = nil, recorders: [RecorderStatus]? = nil) -> ControlResponse {
        ControlResponse(status: "ok", message: message, session_state: state, recorders: recorders)
    }

    static func error(_ message: String) -> ControlResponse {
        ControlResponse(status: "error", message: message)
    }
}
