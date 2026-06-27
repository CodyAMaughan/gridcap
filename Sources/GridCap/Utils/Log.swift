import Foundation

/// Diagnostic logging to stderr, gated behind `--verbose`.
///
/// All structured output goes to stdout as JSON; debug chatter goes to stderr
/// only when verbose mode is enabled, so it never pollutes machine-readable output.
enum Log {
    /// Set once from the command layer (e.g. `record --verbose`).
    static var verbose = false

    /// Write a debug line to stderr when verbose mode is on. No-op otherwise.
    static func debug(_ message: @autoclosure () -> String) {
        guard verbose else { return }
        FileHandle.standardError.write("[gridcap] \(message())\n".data(using: .utf8)!)
    }

    /// Write an always-visible status line to stderr (kept out of stdout JSON).
    static func status(_ message: String) {
        FileHandle.standardError.write("\(message)\n".data(using: .utf8)!)
    }
}
