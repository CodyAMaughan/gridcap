import Foundation

/// Installs SIGINT and SIGTERM handlers that set a flag. Poll `SignalHandler.interrupted` to check.
enum SignalHandler {
    private static var intSource: DispatchSourceSignal?
    private static var termSource: DispatchSourceSignal?

    /// Set to `true` when SIGINT or SIGTERM is received.
    /// Uses a dedicated queue so the flag is set even when the main thread is
    /// occupied by the Swift Concurrency executor (Task.sleep doesn't pump
    /// the GCD main queue).
    static var interrupted = false

    /// Install the handler once. Safe to call multiple times.
    static func install() {
        guard intSource == nil else { return }
        let q = DispatchQueue(label: "signal-handler")

        // SIGINT (Ctrl+C)
        signal(SIGINT, SIG_IGN)
        let intSrc = DispatchSource.makeSignalSource(signal: SIGINT, queue: q)
        intSrc.setEventHandler { interrupted = true }
        intSrc.resume()
        intSource = intSrc

        // SIGTERM (kill / TaskStop)
        signal(SIGTERM, SIG_IGN)
        let termSrc = DispatchSource.makeSignalSource(signal: SIGTERM, queue: q)
        termSrc.setEventHandler { interrupted = true }
        termSrc.resume()
        termSource = termSrc
    }
}
