import AppKit
import ApplicationServices

/// Owns the Accessibility-permission lifecycle.
///
/// The app needs Accessibility (AX) permission to:
///   - read window positions/sizes (kAXPositionAttribute, kAXSizeAttribute)
///   - subscribe to AXObserver notifications when windows move
///   - (later, M3) install a CGEventTap to track drag events with zero delay
///
/// Permission is tied to the binary path. With `swift run`, that's
/// `.build/arm64-apple-macosx/debug/CatPet` — the user grants it once and
/// it persists across rebuilds.
enum AccessibilityGate {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Triggers macOS's "Add to Accessibility" prompt + System Settings deeplink.
    @discardableResult
    static func requestTrust() -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    /// Polls every `interval` seconds until the process is trusted, then calls `onGranted` on the main queue.
    /// Returns a cancel handle (`.invalidate()` to stop polling early).
    @discardableResult
    static func waitUntilTrusted(interval: TimeInterval = 1.0, onGranted: @escaping () -> Void) -> Timer {
        if isTrusted {
            DispatchQueue.main.async(execute: onGranted)
            return Timer()
        }
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { t in
            if isTrusted {
                t.invalidate()
                onGranted()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
}
