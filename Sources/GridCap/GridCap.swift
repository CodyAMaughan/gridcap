import ArgumentParser

@main
struct GridCap: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "gridcap",
        abstract: "Screen capture toolkit for per-window recording on macOS.",
        version: "0.1.0",
        subcommands: [
            ListCommand.self,
            ArrangeCommand.self,
            ScreenshotCommand.self,
            RecordCommand.self,
            MCPCommand.self,
            StopCommand.self,
            PauseCommand.self,
            ResumeCommand.self,
            StatusCommand.self,
            AddWindowCommand.self,
            RemoveWindowCommand.self,
        ]
    )
}
