import ArgumentParser
import Foundation

struct AddWindowCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add-window",
        abstract: "Add a window to a running recording session."
    )

    @Option(name: .long, help: "Session ID of the recording.")
    var sessionId: String

    @Option(name: .long, help: "Window ID to add to the recording.")
    var window: UInt32

    func run() throws {
        let request = ControlRequest(command: .addWindow, window_id: window)
        let response = try ControlClient.send(sessionID: sessionId, request: request)
        let data = try JSONEncoder.prettyEncoder.encode(response)
        print(String(data: data, encoding: .utf8)!)
    }
}
