import Foundation
import ScreenCaptureKit
import CoreMedia

/// Orchestrates multi-window recording with a shared time reference.
final class SessionCoordinator {
    let sessionID: String
    let outputDir: URL
    let fps: Int
    let duration: Double?

    private var recorders: [StreamRecorder] = []
    private let recordersLock = NSLock()
    private let referenceStartTime = ReferenceTime()

    /// Thread-safe access to recorders — avoids NSLock warnings in async contexts.
    private func withRecordersLock<T>(_ body: () -> T) -> T {
        recordersLock.lock()
        defer { recordersLock.unlock() }
        return body()
    }

    /// Set via requestStop() from the control channel.
    private(set) var stopRequested = false

    /// Current session state.
    private(set) var sessionState: SessionState = .recording

    init(sessionID: String, outputDir: URL, fps: Int, duration: Double?) {
        self.sessionID = sessionID
        self.outputDir = outputDir
        self.fps = fps
        self.duration = duration
    }

    // MARK: - Recording lifecycle

    /// Start recording the specified window IDs.
    func start(windowIDs: [UInt32]) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true
        )

        var windowsToRecord: [(UInt32, SCWindow)] = []
        for wid in windowIDs {
            if let scWindow = content.windows.first(where: { $0.windowID == wid }) {
                windowsToRecord.append((wid, scWindow))
            } else {
                throw GridCapError.windowNotFound(wid)
            }
        }

        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        for (wid, scWindow) in windowsToRecord {
            let filename = "window_\(wid)_\(sessionID).mp4"
            let fileURL = outputDir.appendingPathComponent(filename)

            let recorder = StreamRecorder(
                windowID: wid,
                outputURL: fileURL,
                fps: fps,
                referenceStartTime: referenceStartTime
            )

            withRecordersLock { recorders.append(recorder) }

            try await recorder.start(window: scWindow)
        }
    }

    /// Wait for the recording session to finish (via duration, SIGINT, or stopRequested).
    func waitForCompletion() async {
        if let duration = duration {
            let endTime = Date().addingTimeInterval(duration)
            while Date() < endTime && !SignalHandler.interrupted && !stopRequested {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
        } else {
            while !SignalHandler.interrupted && !stopRequested {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
        }
    }

    /// Stop all recorders and return the result summary.
    func stop() async -> RecordResult {
        sessionState = .stopping

        let currentRecorders = withRecordersLock { recorders }

        await withTaskGroup(of: Void.self) { group in
            for recorder in currentRecorders {
                group.addTask {
                    await recorder.stop()
                }
            }
        }

        sessionState = .stopped

        let entries = currentRecorders.map { recorder in
            RecordingEntry(
                window_id: recorder.windowID,
                file: recorder.outputURL.path,
                duration_seconds: round(recorder.recordedDuration * 10) / 10
            )
        }

        return RecordResult(
            status: "ok",
            session_id: sessionID,
            recordings: entries
        )
    }

    // MARK: - Control channel methods

    /// Request a graceful stop from the control channel.
    func requestStop() -> ControlResponse {
        stopRequested = true
        return .ok("Stop requested", state: .stopping)
    }

    /// Pause all recorders — frames are dropped but streams stay alive.
    func pause() -> ControlResponse {
        guard sessionState == .recording else {
            return .error("Session is not recording (state: \(sessionState.rawValue))")
        }

        let currentRecorders = withRecordersLock { recorders }

        for recorder in currentRecorders {
            recorder.pause()
        }
        sessionState = .paused
        return .ok("Session paused", state: .paused)
    }

    /// Resume all recorders.
    func resume() -> ControlResponse {
        guard sessionState == .paused else {
            return .error("Session is not paused (state: \(sessionState.rawValue))")
        }

        let currentRecorders = withRecordersLock { recorders }

        for recorder in currentRecorders {
            recorder.resume()
        }
        sessionState = .recording
        return .ok("Session resumed", state: .recording)
    }

    /// Get status of the session and all recorders.
    func getStatus() -> ControlResponse {
        let currentRecorders = withRecordersLock { recorders }

        let recorderStatuses = currentRecorders.map { recorder in
            RecorderStatus(
                window_id: recorder.windowID,
                file: recorder.outputURL.path,
                frame_count: recorder.frameCount,
                duration_seconds: round(recorder.recordedDuration * 10) / 10,
                file_size_bytes: recorder.fileSize,
                is_paused: recorder.isPaused
            )
        }

        return .ok("Session status", state: sessionState, recorders: recorderStatuses)
    }

    /// Add a new window to the recording mid-session.
    func addWindow(windowID: UInt32) -> ControlResponse {
        guard sessionState == .recording || sessionState == .paused else {
            return .error("Cannot add window — session state: \(sessionState.rawValue)")
        }

        // Check if already recording this window
        let alreadyRecording = withRecordersLock { recorders.contains { $0.windowID == windowID } }

        if alreadyRecording {
            return .error("Window \(windowID) is already being recorded")
        }

        // Bridge async work from the synchronous socket queue via DispatchSemaphore
        let semaphore = DispatchSemaphore(value: 0)
        var resultResponse: ControlResponse = .error("Unknown error")

        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(
                    false, onScreenWindowsOnly: true
                )
                guard let scWindow = content.windows.first(where: { $0.windowID == windowID }) else {
                    resultResponse = .error("Window \(windowID) not found on screen")
                    semaphore.signal()
                    return
                }

                let filename = "window_\(windowID)_\(self.sessionID).mp4"
                let fileURL = self.outputDir.appendingPathComponent(filename)

                let recorder = StreamRecorder(
                    windowID: windowID,
                    outputURL: fileURL,
                    fps: self.fps,
                    referenceStartTime: self.referenceStartTime
                )

                try await recorder.start(window: scWindow)

                self.withRecordersLock { self.recorders.append(recorder) }

                resultResponse = .ok("Window \(windowID) added to session")
            } catch {
                resultResponse = .error("Failed to add window \(windowID): \(error.localizedDescription)")
            }
            semaphore.signal()
        }

        semaphore.wait()
        return resultResponse
    }

    /// Remove a window from the recording and finalize its MP4.
    func removeWindow(windowID: UInt32) -> ControlResponse {
        let recorder: StreamRecorder? = withRecordersLock {
            guard let index = recorders.firstIndex(where: { $0.windowID == windowID }) else {
                return nil
            }
            return recorders.remove(at: index)
        }

        guard let recorder = recorder else {
            return .error("Window \(windowID) is not being recorded")
        }

        // Bridge async stop from the synchronous socket queue
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            await recorder.stop()
            semaphore.signal()
        }
        semaphore.wait()

        return .ok("Window \(windowID) removed and finalized (\(recorder.outputURL.lastPathComponent))")
    }

    /// Dispatch a control request and return a response.
    func handleControlRequest(_ request: ControlRequest) -> ControlResponse {
        switch request.command {
        case .stop:
            return requestStop()
        case .pause:
            return pause()
        case .resume:
            return resume()
        case .status:
            return getStatus()
        case .addWindow:
            guard let wid = request.window_id else {
                return .error("add_window requires window_id")
            }
            return addWindow(windowID: wid)
        case .removeWindow:
            guard let wid = request.window_id else {
                return .error("remove_window requires window_id")
            }
            return removeWindow(windowID: wid)
        }
    }
}
