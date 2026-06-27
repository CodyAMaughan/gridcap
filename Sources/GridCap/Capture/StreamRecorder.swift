import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreMedia
import CoreVideo

/// Stderr debug helper — gated behind `--verbose`, never pollutes stdout JSON.
private func dbg(_ msg: @autoclosure () -> String) {
    Log.debug(msg())
}

/// Records a single SCStream to an MP4 file via AVAssetWriter.
final class StreamRecorder: NSObject, SCStreamOutput, SCStreamDelegate {
    let windowID: UInt32
    let outputURL: URL
    let fps: Int

    private var stream: SCStream?
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?

    /// Shared across all recorders in a session for sync.
    private let referenceStartTime: ReferenceTime
    private var firstFrameReceived = false
    private(set) var frameCount: Int64 = 0
    private var startTime: CMTime = .zero

    /// Set to true when recording should stop.
    var shouldStop = false

    /// Pause support — frames are dropped while paused, timeline stays continuous.
    private(set) var isPaused = false
    private var pauseStartTime: CMTime?
    private var pauseTimeOffset: CMTime = .zero

    /// Duration of recorded content.
    var recordedDuration: Double {
        guard frameCount > 0 else { return 0 }
        return Double(frameCount) / Double(fps)
    }

    /// File size on disk.
    var fileSize: Int64 {
        (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int64) ?? 0
    }

    func pause() {
        guard !isPaused else { return }
        isPaused = true
        dbg("Window \(windowID): paused")
    }

    func resume() {
        guard isPaused else { return }
        isPaused = false
        // pauseStartTime will be used in didOutputSampleBuffer to calculate the gap
        dbg("Window \(windowID): resumed")
    }

    init(windowID: UInt32, outputURL: URL, fps: Int, referenceStartTime: ReferenceTime) {
        self.windowID = windowID
        self.outputURL = outputURL
        self.fps = fps
        self.referenceStartTime = referenceStartTime
        super.init()
    }

    /// Start capturing the given SCWindow.
    func start(window: SCWindow) async throws {
        dbg("Window \(windowID): frame=\(window.frame), title=\(window.title ?? "<nil>"), app=\(window.owningApplication?.applicationName ?? "<nil>")")

        let filter = SCContentFilter(desktopIndependentWindow: window)

        let config = SCStreamConfiguration()
        config.width = Int(window.frame.width) * 2  // Retina
        config.height = Int(window.frame.height) * 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        config.showsCursor = true
        dbg("Window \(windowID): capture size \(config.width)x\(config.height) @ \(fps) fps")

        // Set up AVAssetWriter
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        dbg("Window \(windowID): AVAssetWriter created for \(outputURL.lastPathComponent)")

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: config.width,
            AVVideoHeightKey: config.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 8_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ],
        ]

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = true

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: config.width,
                kCVPixelBufferHeightKey as String: config.height,
            ]
        )

        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        dbg("Window \(windowID): AVAssetWriter status after startWriting: \(writer.status.rawValue)")

        self.assetWriter = writer
        self.videoInput = input
        self.pixelBufferAdaptor = adaptor

        // Create and start stream (self as delegate to catch errors)
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global(qos: .userInitiated))
        dbg("Window \(windowID): calling startCapture()...")
        do {
            try await stream.startCapture()
            dbg("Window \(windowID): startCapture() succeeded")
        } catch {
            dbg("Window \(windowID): startCapture() FAILED: \(error)")
            throw error
        }
        self.stream = stream
    }

    /// Stop capturing and finalize the file.
    func stop() async {
        dbg("Window \(windowID): stop() called — frameCount=\(frameCount), delegateCallCount=\(delegateCallCount)")
        shouldStop = true
        if let stream = stream {
            dbg("Window \(windowID): calling stopCapture()...")
            try? await stream.stopCapture()
            dbg("Window \(windowID): stopCapture() done")
        }

        guard let writer = assetWriter, writer.status == .writing else {
            dbg("Window \(windowID): skipping finalization — writer status \(assetWriter?.status.rawValue ?? -1)")
            return
        }

        // Let queued frames drain through the encoder before finalizing.
        try? await Task.sleep(nanoseconds: 200_000_000) // 200ms

        dbg("Window \(windowID): markAsFinished + finishWriting...")
        videoInput?.markAsFinished()
        await writer.finishWriting()
        dbg("Window \(windowID): finishWriting done — status \(writer.status.rawValue)")

        if writer.status == .failed {
            dbg("Window \(windowID): AVAssetWriter FAILED: \(writer.error?.localizedDescription ?? "unknown")")
        }
    }

    // MARK: - SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        dbg("Window \(windowID): SCStream stopped with error: \(error)")
    }

    // MARK: - SCStreamOutput

    private var delegateCallCount: Int64 = 0

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        delegateCallCount += 1
        if delegateCallCount <= 3 || delegateCallCount % 100 == 0 {
            dbg("Window \(windowID): didOutputSampleBuffer #\(delegateCallCount) type=\(type == .screen ? "screen" : "audio") shouldStop=\(shouldStop)")
        }

        guard type == .screen, !shouldStop else { return }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        // Track pause timing even while paused — record when pause started
        if isPaused {
            if pauseStartTime == nil {
                pauseStartTime = pts
                dbg("Window \(windowID): pause gap started at pts=\(pts.seconds)")
            }
            return
        }

        // If we just resumed, accumulate the pause gap into the offset
        if let pauseStart = pauseStartTime {
            let gap = CMTimeSubtract(pts, pauseStart)
            pauseTimeOffset = CMTimeAdd(pauseTimeOffset, gap)
            pauseStartTime = nil
            dbg("Window \(windowID): pause gap ended, offset now \(pauseTimeOffset.seconds)s")
        }

        guard let videoInput = videoInput, videoInput.isReadyForMoreMediaData else {
            if delegateCallCount <= 5 {
                dbg("Window \(windowID): videoInput not ready (isReadyForMoreMediaData=\(videoInput?.isReadyForMoreMediaData ?? false))")
            }
            return
        }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            if delegateCallCount <= 5 {
                dbg("Window \(windowID): no pixel buffer in sample")
            }
            return
        }

        // Set shared reference time from first frame across all recorders
        if !firstFrameReceived {
            firstFrameReceived = true
            referenceStartTime.setIfFirst(pts)
            startTime = pts
            dbg("Window \(windowID): first frame received, pts=\(pts.seconds)")
        }

        // Compute time relative to shared reference, minus accumulated pause time
        guard let refTime = referenceStartTime.value else { return }
        let relativeTime = CMTimeSubtract(CMTimeSubtract(pts, refTime), pauseTimeOffset)

        if relativeTime.seconds >= 0 {
            pixelBufferAdaptor?.append(pixelBuffer, withPresentationTime: relativeTime)
            frameCount += 1
        }
    }
}

// MARK: - Shared Reference Time

/// Thread-safe shared reference timestamp for syncing multiple recorders.
final class ReferenceTime: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: CMTime?

    var value: CMTime? {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    /// Sets the reference time only if it hasn't been set yet (first writer wins).
    func setIfFirst(_ time: CMTime) {
        lock.lock()
        defer { lock.unlock() }
        if _value == nil {
            _value = time
        }
    }
}
