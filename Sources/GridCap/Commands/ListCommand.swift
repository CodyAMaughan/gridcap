import ArgumentParser
import Foundation
import ApplicationServices

struct ListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List visible windows with their IDs, titles, and bounds."
    )

    @Option(name: .long, help: "Filter by app name (case-insensitive substring match).")
    var appFilter: String?

    @Flag(name: .long, help: "Check screen recording permission status.")
    var checkPermission = false

    func run() async throws {
        if checkPermission {
            let status = await WindowManager.permissionStatus()
            let data = try JSONEncoder.prettyEncoder.encode(status)
            print(String(data: data, encoding: .utf8)!)
            return
        }

        let windows = try await WindowManager.listWindows(appFilter: appFilter)
        let data = try JSONEncoder.prettyEncoder.encode(windows)
        print(String(data: data, encoding: .utf8)!)
    }
}

extension JSONEncoder {
    static var prettyEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
