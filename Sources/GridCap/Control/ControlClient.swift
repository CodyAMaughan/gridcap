import Foundation

/// Connects to a running gridcap session via Unix domain socket and sends a control request.
enum ControlClient {
    /// Send a control request to the session and return the response.
    static func send(sessionID: String, request: ControlRequest) throws -> ControlResponse {
        let socketPath = "/tmp/gridcap-\(sessionID).sock"

        // Create socket
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw GridCapError.recordingError("Failed to create socket: \(String(cString: strerror(errno)))")
        }
        defer { close(fd) }

        // Connect
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &addr.sun_path) { pathPtr in
            pathPtr.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: pathPtr.pointee)) { charPtr in
                _ = socketPath.withCString { strncpy(charPtr, $0, MemoryLayout.size(ofValue: pathPtr.pointee) - 1) }
            }
        }

        let connectResult = withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                connect(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else {
            throw GridCapError.recordingError(
                "Cannot connect to session '\(sessionID)' — is it running? (socket: \(socketPath), error: \(String(cString: strerror(errno))))"
            )
        }

        // Send request
        let requestData = try JSONEncoder().encode(request)
        _ = requestData.withUnsafeBytes { rawBuffer in
            write(fd, rawBuffer.baseAddress!, rawBuffer.count)
        }

        // Shutdown write side to signal end of request
        shutdown(fd, SHUT_WR)

        // Read response
        var responseData = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let bytesRead = read(fd, &buffer, buffer.count)
            if bytesRead <= 0 { break }
            responseData.append(contentsOf: buffer[0..<bytesRead])
        }

        guard !responseData.isEmpty else {
            throw GridCapError.recordingError("Empty response from session '\(sessionID)'")
        }

        return try JSONDecoder().decode(ControlResponse.self, from: responseData)
    }
}
