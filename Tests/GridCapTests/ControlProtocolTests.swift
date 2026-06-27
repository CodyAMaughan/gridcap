import XCTest
@testable import gridcap

/// Round-trip and wire-format tests for the control protocol. These exercise the
/// JSON contract the CLI exposes over its stdout and control socket — no screen
/// recording permission or live windows required, so they run anywhere.
final class ControlProtocolTests: XCTestCase {

    func testControlCommandWireValues() {
        // The socket protocol depends on these exact snake_case strings.
        XCTAssertEqual(ControlCommand.stop.rawValue, "stop")
        XCTAssertEqual(ControlCommand.addWindow.rawValue, "add_window")
        XCTAssertEqual(ControlCommand.removeWindow.rawValue, "remove_window")
        XCTAssertEqual(ControlCommand(rawValue: "add_window"), .addWindow)
    }

    func testControlRequestRoundTrips() throws {
        let request = ControlRequest(command: .addWindow, window_id: 42)
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(ControlRequest.self, from: data)
        XCTAssertEqual(decoded.command, .addWindow)
        XCTAssertEqual(decoded.window_id, 42)
    }

    func testControlRequestOmitsWindowIDByDefault() {
        XCTAssertNil(ControlRequest(command: .status).window_id)
    }

    func testControlResponseWithRecordersRoundTrips() throws {
        let recorder = RecorderStatus(
            window_id: 7,
            file: "/tmp/window_7_abcd.mp4",
            frame_count: 300,
            duration_seconds: 10.0,
            file_size_bytes: 1_234_567,
            is_paused: false
        )
        let response = ControlResponse.ok("Session status", state: .recording, recorders: [recorder])
        let data = try JSONEncoder.prettyEncoder.encode(response)
        let decoded = try JSONDecoder().decode(ControlResponse.self, from: data)

        XCTAssertEqual(decoded.status, "ok")
        XCTAssertEqual(decoded.session_state, .recording)
        XCTAssertEqual(decoded.recorders?.count, 1)
        XCTAssertEqual(decoded.recorders?.first?.window_id, 7)
        XCTAssertEqual(decoded.recorders?.first?.is_paused, false)
    }

    func testErrorResponseHasNoState() {
        let response = ControlResponse.error("Window 99 not found")
        XCTAssertEqual(response.status, "error")
        XCTAssertNil(response.session_state)
        XCTAssertNil(response.recorders)
    }

    func testWindowInfoDecodesSnakeCaseKeys() throws {
        let json = """
        {
          "window_id": 123,
          "title": "Terminal",
          "app_name": "iTerm2",
          "app_bundle_id": "com.googlecode.iterm2",
          "bounds": { "x": 0, "y": 0, "width": 800, "height": 600 }
        }
        """.data(using: .utf8)!
        let info = try JSONDecoder().decode(WindowInfo.self, from: json)
        XCTAssertEqual(info.window_id, 123)
        XCTAssertEqual(info.app_name, "iTerm2")
        XCTAssertEqual(info.bounds.width, 800)
    }

    func testPrettyEncoderSortsKeys() throws {
        let bounds = WindowBounds(x: 1, y: 2, width: 3, height: 4)
        let data = try JSONEncoder.prettyEncoder.encode(bounds)
        let string = String(data: data, encoding: .utf8)!
        // .sortedKeys must put "height" before "width".
        let heightIdx = string.range(of: "height")!.lowerBound
        let widthIdx = string.range(of: "width")!.lowerBound
        XCTAssertLessThan(heightIdx, widthIdx)
    }
}
