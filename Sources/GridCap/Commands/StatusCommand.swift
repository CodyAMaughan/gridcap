import ArgumentParser
import Foundation

struct StatusCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Get the status of a running recording session."
    )

    @Option(name: .long, help: "Session ID of the recording to query.")
    var sessionId: String

    func run() throws {
        let request = ControlRequest(command: .status)
        let response = try ControlClient.send(sessionID: sessionId, request: request)
        let data = try JSONEncoder.prettyEncoder.encode(response)
        print(String(data: data, encoding: .utf8)!)
    }
}
