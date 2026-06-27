import ArgumentParser
import Foundation
import CoreGraphics
import MCP

/// `gridcap mcp` — exposes gridcap as a Model Context Protocol server over stdio.
///
/// This is the portable, cross-harness path: any MCP-capable agent (Claude Code,
/// Codex, Cursor, Zed, ...) can point at `gridcap mcp` and get the same window
/// listing, arranging, screenshotting, and per-window recording the CLI offers.
///
/// The synchronous operations (list/arrange/screenshot/permissions) and the control
/// operations (status/pause/resume/stop/add/remove) call the very same internals the
/// CLI subcommands use. Recording is long-running, so `start_recording` launches a
/// detached `gridcap record` child and returns its session id; the control tools then
/// drive it over its Unix socket — exactly mirroring the CLI workflow.
struct MCPCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp",
        abstract: "Run gridcap as an MCP server over stdio (for Codex, Claude Code, and other agents)."
    )

    func run() async throws {
        // Force Core Graphics window-server init (see RecordCommand) so capture works
        // when spawned from a non-interactive shell (e.g. by an agent harness).
        _ = CGMainDisplayID()

        let server = Server(
            name: "gridcap",
            version: "0.1.0",
            capabilities: .init(tools: .init(listChanged: false))
        )

        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: MCPTools.all)
        }

        await server.withMethodHandler(CallTool.self) { params in
            await MCPTools.call(name: params.name, arguments: params.arguments)
        }

        let transport = StdioTransport()
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }
}

// MARK: - Tool definitions & dispatch

enum MCPTools {

    /// JSON-Schema fragment for a single required string parameter named `session_id`.
    private static let sessionIdSchema: Value = [
        "type": "object",
        "properties": ["session_id": ["type": "string", "description": "The recording session id."]],
        "required": ["session_id"],
    ]

    static let all: [Tool] = [
        Tool(
            name: "check_permissions",
            description: "Report whether Screen Recording and Accessibility permissions are granted. Call this before recording.",
            inputSchema: ["type": "object", "properties": [:]]
        ),
        Tool(
            name: "list_windows",
            description: "List on-screen windows with their numeric window_id, title, app name, and bounds. Optionally filter by app name or title substring.",
            inputSchema: [
                "type": "object",
                "properties": ["app_filter": ["type": "string", "description": "Case-insensitive substring matched against app name or window title."]],
            ]
        ),
        Tool(
            name: "arrange_window",
            description: "Move and resize a window by id (requires Accessibility permission). Useful to set a clean layout before recording.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "window_id": ["type": "integer", "description": "Numeric window id from list_windows."],
                    "x": ["type": "number"], "y": ["type": "number"],
                    "width": ["type": "number"], "height": ["type": "number"],
                ],
                "required": ["window_id", "x", "y", "width", "height"],
            ]
        ),
        Tool(
            name: "screenshot_window",
            description: "Capture a single window to a PNG file at output_path.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "window_id": ["type": "integer", "description": "Numeric window id from list_windows."],
                    "output_path": ["type": "string", "description": "Destination PNG path."],
                ],
                "required": ["window_id", "output_path"],
            ]
        ),
        Tool(
            name: "start_recording",
            description: "Start recording one or more windows, each to its own MP4 in output_dir. Returns a session_id used by the other recording tools. If duration is omitted, recording runs until stop_recording.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "window_ids": ["type": "array", "items": ["type": "integer"], "description": "Window ids to record simultaneously."],
                    "output_dir": ["type": "string", "description": "Directory for the MP4 files."],
                    "fps": ["type": "integer", "description": "Frames per second (default 30)."],
                    "duration": ["type": "number", "description": "Optional fixed duration in seconds."],
                    "session_id": ["type": "string", "description": "Optional explicit session id; auto-generated if omitted."],
                ],
                "required": ["window_ids", "output_dir"],
            ]
        ),
        Tool(name: "recording_status", description: "Get status (frame counts, file sizes, paused state) of a running recording session.", inputSchema: sessionIdSchema),
        Tool(name: "pause_recording", description: "Pause a running recording session. Frames are dropped; the output timeline stays gap-free.", inputSchema: sessionIdSchema),
        Tool(name: "resume_recording", description: "Resume a paused recording session.", inputSchema: sessionIdSchema),
        Tool(name: "stop_recording", description: "Stop a recording session, finalize all MP4s, and end the session.", inputSchema: sessionIdSchema),
        Tool(
            name: "add_window",
            description: "Add another window to a running recording session mid-session.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "session_id": ["type": "string"],
                    "window_id": ["type": "integer"],
                ],
                "required": ["session_id", "window_id"],
            ]
        ),
        Tool(
            name: "remove_window",
            description: "Stop recording a single window in a session and finalize just its MP4.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "session_id": ["type": "string"],
                    "window_id": ["type": "integer"],
                ],
                "required": ["session_id", "window_id"],
            ]
        ),
    ]

    static func call(name: String, arguments: [String: Value]?) async -> CallTool.Result {
        do {
            switch name {
            case "check_permissions":
                return ok(try encode(await WindowManager.permissionStatus()))

            case "list_windows":
                let windows = try await WindowManager.listWindows(appFilter: stringArg(arguments, "app_filter"))
                return ok(try encode(windows))

            case "arrange_window":
                let bounds = try WindowManager.arrangeWindow(
                    windowID: try requireUInt32(arguments, "window_id"),
                    x: try requireDouble(arguments, "x"),
                    y: try requireDouble(arguments, "y"),
                    width: try requireDouble(arguments, "width"),
                    height: try requireDouble(arguments, "height")
                )
                return ok(try encode(ArrangeResult(status: "ok", window_id: try requireUInt32(arguments, "window_id"), bounds: bounds)))

            case "screenshot_window":
                let result = try WindowManager.captureScreenshot(
                    windowID: try requireUInt32(arguments, "window_id"),
                    outputPath: try requireString(arguments, "output_path")
                )
                return ok(try encode(result))

            case "start_recording":
                return ok(try await startRecording(arguments))

            case "recording_status": return try control(arguments, .status)
            case "pause_recording":  return try control(arguments, .pause)
            case "resume_recording": return try control(arguments, .resume)
            case "stop_recording":   return try control(arguments, .stop)
            case "add_window":       return try control(arguments, .addWindow, windowID: try requireUInt32(arguments, "window_id"))
            case "remove_window":    return try control(arguments, .removeWindow, windowID: try requireUInt32(arguments, "window_id"))

            default:
                return error("Unknown tool: \(name)")
            }
        } catch let e as MCPToolError {
            return error(e.message)
        } catch let err {
            return error(err.localizedDescription)
        }
    }

    // MARK: - Recording

    private struct StartRecordingResult: Encodable {
        let status: String
        let session_id: String
        let socket_path: String
        let output_dir: String
        let window_ids: [UInt32]
        let files: [String]
    }

    private static func startRecording(_ args: [String: Value]?) async throws -> String {
        let windowIDs = uint32Array(args, "window_ids")
        guard !windowIDs.isEmpty else { throw MCPToolError("window_ids must contain at least one window id") }
        let outputDir = try requireString(args, "output_dir")
        let fps = intArg(args, "fps") ?? 30
        let sid = stringArg(args, "session_id") ?? UUID().uuidString.lowercased().prefix(8).description

        let selfPath = Bundle.main.executablePath ?? CommandLine.arguments[0]
        var recordArgs = [
            "record",
            "--windows", windowIDs.map(String.init).joined(separator: ","),
            "--output-dir", outputDir,
            "--fps", String(fps),
            "--session-id", sid,
        ]
        if let duration = doubleArg(args, "duration") {
            recordArgs += ["--duration", String(duration)]
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: selfPath)
        proc.arguments = recordArgs
        // Detach the child's I/O so its JSON summary never corrupts our stdio MCP stream.
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        proc.standardInput = FileHandle.nullDevice
        try proc.run()

        // Wait for the control socket to appear so subsequent control tools work.
        let socketPath = "/tmp/gridcap-\(sid).sock"
        var waited = 0.0
        while !FileManager.default.fileExists(atPath: socketPath) && waited < 5.0 {
            try await Task.sleep(nanoseconds: 100_000_000)
            waited += 0.1
        }
        guard FileManager.default.fileExists(atPath: socketPath) else {
            throw MCPToolError("Recording failed to start (control socket never appeared). Check screen recording permission with check_permissions.")
        }

        let result = StartRecordingResult(
            status: "ok",
            session_id: sid,
            socket_path: socketPath,
            output_dir: outputDir,
            window_ids: windowIDs,
            files: windowIDs.map { "\(outputDir)/window_\($0)_\(sid).mp4" }
        )
        return try encode(result)
    }

    private static func control(_ args: [String: Value]?, _ command: ControlCommand, windowID: UInt32? = nil) throws -> CallTool.Result {
        let sid = try requireString(args, "session_id")
        let response = try ControlClient.send(sessionID: sid, request: ControlRequest(command: command, window_id: windowID))
        return ok(try encode(response))
    }

    // MARK: - Result helpers

    private static func ok(_ json: String) -> CallTool.Result { .init(content: [.text(text: json)], isError: false) }
    private static func error(_ message: String) -> CallTool.Result {
        .init(content: [.text(text: "{\"status\":\"error\",\"message\":\(jsonString(message))}")], isError: true)
    }

    private static func encode<T: Encodable>(_ value: T) throws -> String {
        String(data: try JSONEncoder.prettyEncoder.encode(value), encoding: .utf8) ?? "{}"
    }
    private static func jsonString(_ s: String) -> String {
        guard let data = try? JSONEncoder().encode(s),
              let str = String(data: data, encoding: .utf8) else { return "\"\"" }
        return str
    }

    // MARK: - Argument extraction

    private static func stringArg(_ args: [String: Value]?, _ key: String) -> String? { args?[key]?.stringValue }
    private static func intArg(_ args: [String: Value]?, _ key: String) -> Int? {
        if let i = args?[key]?.intValue { return i }
        if let d = args?[key]?.doubleValue { return Int(d) }
        if let s = args?[key]?.stringValue { return Int(s) }
        return nil
    }
    private static func doubleArg(_ args: [String: Value]?, _ key: String) -> Double? {
        if let d = args?[key]?.doubleValue { return d }
        if let i = args?[key]?.intValue { return Double(i) }
        if let s = args?[key]?.stringValue { return Double(s) }
        return nil
    }

    private static func uint32Array(_ args: [String: Value]?, _ key: String) -> [UInt32] {
        guard let arr = args?[key]?.arrayValue else {
            // Tolerate a comma-separated string too.
            if let s = args?[key]?.stringValue {
                return s.split(separator: ",").compactMap { UInt32($0.trimmingCharacters(in: .whitespaces)) }
            }
            return []
        }
        return arr.compactMap { v in
            if let i = v.intValue { return UInt32(i) }
            if let d = v.doubleValue { return UInt32(d) }
            if let s = v.stringValue { return UInt32(s) }
            return nil
        }
    }

    private static func requireString(_ args: [String: Value]?, _ key: String) throws -> String {
        guard let v = stringArg(args, key), !v.isEmpty else { throw MCPToolError("Missing required string argument: \(key)") }
        return v
    }
    private static func requireUInt32(_ args: [String: Value]?, _ key: String) throws -> UInt32 {
        guard let i = intArg(args, key), i >= 0 else { throw MCPToolError("Missing or invalid integer argument: \(key)") }
        return UInt32(i)
    }
    private static func requireDouble(_ args: [String: Value]?, _ key: String) throws -> Double {
        guard let d = doubleArg(args, key) else { throw MCPToolError("Missing or invalid number argument: \(key)") }
        return d
    }
}

private struct MCPToolError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}
