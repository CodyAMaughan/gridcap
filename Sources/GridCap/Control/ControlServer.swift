import Foundation

/// Unix domain socket server for controlling a recording session.
final class ControlServer {
    let sessionID: String
    let socketPath: String
    private let coordinator: SessionCoordinator
    private var serverFD: Int32 = -1
    private var running = false
    private let queue = DispatchQueue(label: "gridcap.control-server", qos: .utility)

    init(sessionID: String, coordinator: SessionCoordinator) {
        self.sessionID = sessionID
        self.coordinator = coordinator
        self.socketPath = "/tmp/gridcap-\(sessionID).sock"
    }

    /// Start listening for control connections on a background queue.
    func start() throws {
        // Clean up stale socket
        unlink(socketPath)

        // Create Unix domain socket
        serverFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFD >= 0 else {
            throw GridCapError.recordingError("Failed to create control socket: \(String(cString: strerror(errno)))")
        }

        // Bind
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &addr.sun_path) { pathPtr in
            pathPtr.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: pathPtr.pointee)) { charPtr in
                _ = socketPath.withCString { strncpy(charPtr, $0, MemoryLayout.size(ofValue: pathPtr.pointee) - 1) }
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(serverFD, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            close(serverFD)
            throw GridCapError.recordingError("Failed to bind control socket at \(socketPath): \(String(cString: strerror(errno)))")
        }

        // Listen
        guard listen(serverFD, 5) == 0 else {
            close(serverFD)
            unlink(socketPath)
            throw GridCapError.recordingError("Failed to listen on control socket: \(String(cString: strerror(errno)))")
        }

        running = true

        // Accept connections on a dedicated queue (blocking, not Swift Concurrency)
        queue.async { [weak self] in
            self?.acceptLoop()
        }
    }

    /// Stop the server and clean up.
    func stop() {
        running = false
        if serverFD >= 0 {
            // Closing the fd will unblock accept()
            shutdown(serverFD, SHUT_RDWR)
            close(serverFD)
            serverFD = -1
        }
        unlink(socketPath)
    }

    // MARK: - Private

    private func acceptLoop() {
        while running {
            var clientAddr = sockaddr_un()
            var clientLen = socklen_t(MemoryLayout<sockaddr_un>.size)

            let clientFD = withUnsafeMutablePointer(to: &clientAddr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                    accept(serverFD, sockaddrPtr, &clientLen)
                }
            }

            guard clientFD >= 0 else {
                // accept() returns -1 when socket is closed during shutdown
                break
            }

            handleClient(fd: clientFD)
            close(clientFD)
        }
    }

    private func handleClient(fd: Int32) {
        // Read request (up to 4KB should be more than enough)
        var buffer = [UInt8](repeating: 0, count: 4096)
        let bytesRead = read(fd, &buffer, buffer.count)
        guard bytesRead > 0 else { return }

        let data = Data(buffer[0..<bytesRead])

        let response: ControlResponse
        do {
            let request = try JSONDecoder().decode(ControlRequest.self, from: data)
            response = coordinator.handleControlRequest(request)
        } catch {
            response = .error("Invalid request: \(error.localizedDescription)")
        }

        // Write response
        do {
            let responseData = try JSONEncoder.prettyEncoder.encode(response)
            _ = responseData.withUnsafeBytes { rawBuffer in
                write(fd, rawBuffer.baseAddress!, rawBuffer.count)
            }
        } catch {
            let errorJSON = "{\"status\":\"error\",\"message\":\"Failed to encode response\"}"
            _ = errorJSON.withCString { cstr in
                write(fd, cstr, strlen(cstr))
            }
        }
    }
}
