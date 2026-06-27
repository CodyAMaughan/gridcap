import ArgumentParser
import Foundation
import CoreGraphics
import AppKit
import UniformTypeIdentifiers

struct ScreenshotCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "screenshot",
        abstract: "Capture a screenshot of a specific window."
    )

    @Argument(help: "The window ID to capture.")
    var windowID: UInt32

    @Option(name: .shortAndLong, help: "Output file path (PNG).")
    var output: String

    func run() throws {
        // Use CGWindowListCreateImage for broad compatibility
        guard let image = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            CGWindowID(windowID),
            [.boundsIgnoreFraming, .bestResolution]
        ) else {
            throw GridCapError.captureError("Failed to capture window \(windowID). Check screen recording permission.")
        }

        let outputURL = URL(fileURLWithPath: output)

        // Ensure parent directory exists
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // Write PNG
        guard let dest = CGImageDestinationCreateWithURL(
            outputURL as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else {
            throw GridCapError.captureError("Failed to create image destination at \(output)")
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw GridCapError.captureError("Failed to write PNG to \(output)")
        }

        let result = ScreenshotResult(
            status: "ok",
            path: outputURL.path,
            width: image.width,
            height: image.height
        )

        let data = try JSONEncoder.prettyEncoder.encode(result)
        print(String(data: data, encoding: .utf8)!)
    }
}
