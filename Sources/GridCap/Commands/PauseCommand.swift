import ArgumentParser
import Foundation

struct PauseCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pause",
        abstract: "Pause a running recording session (frames are dropped, streams stay alive)."
    )

    @Option(name: .long, help: "Session ID of the recording to pause.")
    var sessionId: String

    func run() throws {
        let request = ControlRequest(command: .pause)
        let response = try ControlClient.send(sessionID: sessionId, request: request)
        let data = try JSONEncoder.prettyEncoder.encode(response)
        print(String(data: data, encoding: .utf8)!)
    }
}
