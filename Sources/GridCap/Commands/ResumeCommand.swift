import ArgumentParser
import Foundation

struct ResumeCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "resume",
        abstract: "Resume a paused recording session."
    )

    @Option(name: .long, help: "Session ID of the recording to resume.")
    var sessionId: String

    func run() throws {
        let request = ControlRequest(command: .resume)
        let response = try ControlClient.send(sessionID: sessionId, request: request)
        let data = try JSONEncoder.prettyEncoder.encode(response)
        print(String(data: data, encoding: .utf8)!)
    }
}
