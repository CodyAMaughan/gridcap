import ArgumentParser
import Foundation

struct StopCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stop",
        abstract: "Gracefully stop a running recording session."
    )

    @Option(name: .long, help: "Session ID of the recording to stop.")
    var sessionId: String

    func run() throws {
        let request = ControlRequest(command: .stop)
        let response = try ControlClient.send(sessionID: sessionId, request: request)
        let data = try JSONEncoder.prettyEncoder.encode(response)
        print(String(data: data, encoding: .utf8)!)
    }
}
