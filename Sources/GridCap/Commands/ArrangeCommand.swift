import ArgumentParser
import Foundation

struct ArrangeCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "arrange",
        abstract: "Move and resize a window by its ID."
    )

    @Argument(help: "The window ID to arrange.")
    var windowID: UInt32

    @Option(name: .long, help: "X position (pixels from left).")
    var x: Double

    @Option(name: .long, help: "Y position (pixels from top).")
    var y: Double

    @Option(name: .long, help: "Window width in pixels.")
    var width: Double

    @Option(name: .long, help: "Window height in pixels.")
    var height: Double

    func run() throws {
        let newBounds = try WindowManager.arrangeWindow(
            windowID: windowID, x: x, y: y, width: width, height: height
        )

        let result = ArrangeResult(
            status: "ok",
            window_id: windowID,
            bounds: newBounds
        )

        let data = try JSONEncoder.prettyEncoder.encode(result)
        print(String(data: data, encoding: .utf8)!)
    }
}
