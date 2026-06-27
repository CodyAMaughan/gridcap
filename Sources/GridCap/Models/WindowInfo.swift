import Foundation

struct WindowBounds: Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

struct WindowInfo: Codable {
    let window_id: UInt32
    let title: String
    let app_name: String
    let app_bundle_id: String
    let bounds: WindowBounds
}

struct ArrangeResult: Codable {
    let status: String
    let window_id: UInt32
    let bounds: WindowBounds
}

struct ScreenshotResult: Codable {
    let status: String
    let path: String
    let width: Int
    let height: Int
}

struct RecordingEntry: Codable {
    let window_id: UInt32
    let file: String
    let duration_seconds: Double
}

struct RecordResult: Codable {
    let status: String
    let session_id: String
    let recordings: [RecordingEntry]
}

struct PermissionStatus: Codable {
    let screen_recording: String
    let accessibility: String
}
