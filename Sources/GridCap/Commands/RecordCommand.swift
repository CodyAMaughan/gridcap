import ArgumentParser
import Foundation
import CoreGraphics

struct RecordCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "record",
        abstract: "Record one or more windows simultaneously to separate MP4 files."
    )

    @Option(name: .long, help: "Comma-separated window IDs to record.")
    var windows: String

    @Option(name: .long, help: "Output directory for recorded files.")
    var outputDir: String

    @Option(name: .long, help: "Frames per second (default: 30).")
    var fps: Int = 30

    @Option(name: .long, help: "Recording duration in seconds. Omit for indefinite (stop with Ctrl+C).")
    var duration: Double?

    @Option(name: .long, help: "Session ID (default: auto-generated UUID).")
    var sessionId: String?

    @Flag(name: .long, help: "Print verbose per-frame diagnostics to stderr.")
    var verbose = false

    func run() async throws {
        Log.verbose = verbose

        // Force Core Graphics window server initialization.
        // Without this, AVAssetWriterInputPixelBufferAdaptor crashes with
        // CGS_REQUIRE_INIT in non-interactive shells (e.g. spawned by IDE agents).
        _ = CGMainDisplayID()

        // Parse window IDs
        let windowIDs = windows.split(separator: ",").compactMap { UInt32($0.trimmingCharacters(in: .whitespaces)) }
        guard !windowIDs.isEmpty else {
            throw ValidationError("No valid window IDs provided.")
        }

        let sid = sessionId ?? UUID().uuidString.lowercased().prefix(8).description
        let outURL = URL(fileURLWithPath: outputDir)

        // Install signal handler for graceful stop
        SignalHandler.install()

        let coordinator = SessionCoordinator(
            sessionID: sid,
            outputDir: outURL,
            fps: fps,
            duration: duration
        )

        // Start control server for IPC
        let controlServer = ControlServer(sessionID: sid, coordinator: coordinator)
        try controlServer.start()

        // Status to stderr so it doesn't pollute JSON stdout
        Log.status("Recording \(windowIDs.count) window(s)...")
        Log.status("Session ID: \(sid)")
        Log.status("Control socket: \(controlServer.socketPath)")
        if let duration = duration {
            Log.status("Duration: \(duration)s")
        } else {
            Log.status("Press Ctrl+C or run `gridcap stop --session-id \(sid)` to stop.")
        }

        try await coordinator.start(windowIDs: windowIDs)
        await coordinator.waitForCompletion()
        let result = await coordinator.stop()

        controlServer.stop()

        let data = try JSONEncoder.prettyEncoder.encode(result)
        print(String(data: data, encoding: .utf8)!)
    }
}
