import Foundation
import ScreenCaptureKit
import AppKit
import CoreGraphics
import ApplicationServices

/// Enumerates windows via ScreenCaptureKit and manipulates them via Accessibility API.
enum WindowManager {

    // MARK: - Window Enumeration

    /// List on-screen windows, optionally filtered by app name substring.
    static func listWindows(appFilter: String? = nil) async throws -> [WindowInfo] {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true
        )

        var results: [WindowInfo] = []
        for window in content.windows {
            let app = window.owningApplication
            let appName = app?.applicationName ?? ""
            let bundleId = app?.bundleIdentifier ?? ""
            let title = window.title ?? ""

            // Skip windows with no title and tiny size (menu bar items, etc.)
            if title.isEmpty && window.frame.width < 50 && window.frame.height < 50 {
                continue
            }

            if let filter = appFilter {
                let filterLower = filter.lowercased()
                let matchesApp = appName.lowercased().contains(filterLower)
                let matchesTitle = title.lowercased().contains(filterLower)
                if !matchesApp && !matchesTitle { continue }
            }

            let info = WindowInfo(
                window_id: window.windowID,
                title: title,
                app_name: appName,
                app_bundle_id: bundleId,
                bounds: WindowBounds(
                    x: Double(window.frame.origin.x),
                    y: Double(window.frame.origin.y),
                    width: Double(window.frame.width),
                    height: Double(window.frame.height)
                )
            )
            results.append(info)
        }
        return results
    }

    // MARK: - Window Arrangement (Accessibility API)

    /// Move and resize a window using the Accessibility API.
    /// Returns the new bounds after the operation.
    static func arrangeWindow(windowID: UInt32, x: Double, y: Double, width: Double, height: Double) throws -> WindowBounds {
        // Find the PID owning this window via CGWindowList
        guard let pid = findPID(forWindowID: windowID) else {
            throw GridCapError.windowNotFound(windowID)
        }

        let appElement = AXUIElementCreateApplication(pid)

        // Get the list of windows for this app
        var windowsRef: CFTypeRef?
        let windowResult = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        guard windowResult == .success, let windows = windowsRef as? [AXUIElement] else {
            throw GridCapError.accessibilityDenied
        }

        // Find the matching window — try to match by comparing bounds
        // since AX doesn't expose CGWindowID directly
        guard let targetWindow = findAXWindow(windows: windows, windowID: windowID) else {
            throw GridCapError.windowNotFound(windowID)
        }

        // Set position
        var point = CGPoint(x: x, y: y)
        guard let posValue = AXValueCreate(.cgPoint, &point) else {
            throw GridCapError.axError("Failed to create position value")
        }
        AXUIElementSetAttributeValue(targetWindow, kAXPositionAttribute as CFString, posValue)

        // Set size
        var size = CGSize(width: width, height: height)
        guard let sizeValue = AXValueCreate(.cgSize, &size) else {
            throw GridCapError.axError("Failed to create size value")
        }
        AXUIElementSetAttributeValue(targetWindow, kAXSizeAttribute as CFString, sizeValue)

        // Read back actual bounds
        let actualBounds = readBounds(of: targetWindow)

        return WindowBounds(
            x: actualBounds.map { Double($0.origin.x) } ?? x,
            y: actualBounds.map { Double($0.origin.y) } ?? y,
            width: actualBounds.map { Double($0.size.width) } ?? width,
            height: actualBounds.map { Double($0.size.height) } ?? height
        )
    }

    // MARK: - Permission Check

    static func isAccessibilityGranted() -> Bool {
        return AXIsProcessTrusted()
    }

    // MARK: - Helpers

    /// Find the PID that owns a given CGWindowID.
    private static func findPID(forWindowID windowID: UInt32) -> pid_t? {
        let options = CGWindowListOption([.optionAll])
        guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        for info in infoList {
            if let wid = info[kCGWindowNumber as String] as? UInt32, wid == windowID {
                return info[kCGWindowOwnerPID as String] as? pid_t
            }
        }
        return nil
    }

    /// Try to find the AXUIElement window matching a CGWindowID by comparing bounds.
    private static func findAXWindow(windows: [AXUIElement], windowID: UInt32) -> AXUIElement? {
        // Get CG bounds for the target window
        let options = CGWindowListOption([.optionAll])
        guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        var targetBounds: CGRect?
        for info in infoList {
            if let wid = info[kCGWindowNumber as String] as? UInt32, wid == windowID {
                if let boundsDict = info[kCGWindowBounds as String] as? [String: Any] {
                    let x = boundsDict["X"] as? Double ?? 0
                    let y = boundsDict["Y"] as? Double ?? 0
                    let w = boundsDict["Width"] as? Double ?? 0
                    let h = boundsDict["Height"] as? Double ?? 0
                    targetBounds = CGRect(x: x, y: y, width: w, height: h)
                }
                break
            }
        }
        guard let target = targetBounds else { return windows.first }

        // Match by bounds
        for win in windows {
            if let bounds = readBounds(of: win) {
                if abs(bounds.origin.x - target.origin.x) < 5 &&
                   abs(bounds.origin.y - target.origin.y) < 5 &&
                   abs(bounds.size.width - target.size.width) < 5 &&
                   abs(bounds.size.height - target.size.height) < 5 {
                    return win
                }
            }
        }
        // Fallback to first window
        return windows.first
    }

    /// Read position + size from an AXUIElement window.
    private static func readBounds(of element: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?

        AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef)
        AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef)

        var point = CGPoint.zero
        var size = CGSize.zero

        if let posVal = posRef {
            AXValueGetValue(posVal as! AXValue, .cgPoint, &point)
        }
        if let sizeVal = sizeRef {
            AXValueGetValue(sizeVal as! AXValue, .cgSize, &size)
        }

        if posRef != nil || sizeRef != nil {
            return CGRect(origin: point, size: size)
        }
        return nil
    }
}

// MARK: - Errors

enum GridCapError: LocalizedError {
    case windowNotFound(UInt32)
    case accessibilityDenied
    case axError(String)
    case captureError(String)
    case recordingError(String)

    var errorDescription: String? {
        switch self {
        case .windowNotFound(let id): return "Window \(id) not found"
        case .accessibilityDenied: return "Accessibility permission denied. Grant access in System Settings > Privacy > Accessibility."
        case .axError(let msg): return "Accessibility error: \(msg)"
        case .captureError(let msg): return "Capture error: \(msg)"
        case .recordingError(let msg): return "Recording error: \(msg)"
        }
    }
}
