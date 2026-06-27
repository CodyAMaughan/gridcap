import ArgumentParser
import Foundation

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
        let result = try WindowManager.captureScreenshot(windowID: windowID, outputPath: output)
        let data = try JSONEncoder.prettyEncoder.encode(result)
        print(String(data: data, encoding: .utf8)!)
    }
}
