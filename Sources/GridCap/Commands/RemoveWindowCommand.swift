import ArgumentParser
import Foundation

struct RemoveWindowCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "remove-window",
        abstract: "Remove a window from a running recording session and finalize its MP4."
    )

    @Option(name: .long, help: "Session ID of the recording.")
    var sessionId: String

    @Option(name: .long, help: "Window ID to remove from the recording.")
    var window: UInt32

    func run() throws {
        let request = ControlRequest(command: .removeWindow, window_id: window)
        let response = try ControlClient.send(sessionID: sessionId, request: request)
        let data = try JSONEncoder.prettyEncoder.encode(response)
        print(String(data: data, encoding: .utf8)!)
    }
}
