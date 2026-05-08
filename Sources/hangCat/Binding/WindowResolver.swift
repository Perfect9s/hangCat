import AppKit
import CoreGraphics

/// Looks up which on-screen window sits under a given screen point.
/// Used when the user drops the cat to figure out which window they
/// dropped it on, so we can re-pin to that window.
enum WindowResolver {
    struct Hit {
        let pid: pid_t
        let windowID: CGWindowID
        let owner: String
        /// Bounds in CG (top-left origin) coordinates.
        let cgBounds: CGRect
    }

    /// Returns the topmost qualifying window under `cgPoint`, or nil if none.
    /// `excludingPID` lets us skip our own process (the cat window).
    static func findWindow(under cgPoint: CGPoint, excludingPID: pid_t) -> Hit? {
        let opts: CGWindowListOption = [.optionOnScreenOnly]
        guard let info = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        // CGWindowListCopyWindowInfo returns front-to-back z-order, so the
        // first match wins.
        for w in info {
            let layer = (w[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            if layer != 0 { continue }

            guard let pid = w[kCGWindowOwnerPID as String] as? Int32, pid != excludingPID else { continue }

            let owner = w[kCGWindowOwnerName as String] as? String ?? ""
            if BindingManager.blockedOwnerNames.contains(owner) { continue }

            guard let bounds = w[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
            let rect = CGRect(
                x: bounds["X"] ?? 0,
                y: bounds["Y"] ?? 0,
                width: bounds["Width"] ?? 0,
                height: bounds["Height"] ?? 0
            )
            // Skip trivial windows (tooltips, menus, etc).
            if rect.size.width < 100 || rect.size.height < 60 { continue }

            if rect.contains(cgPoint) {
                guard let windowID = w[kCGWindowNumber as String] as? UInt32 else { continue }
                return Hit(pid: pid, windowID: windowID, owner: owner, cgBounds: rect)
            }
        }
        return nil
    }
}

extension Notification.Name {
    /// Posted by PetWindowController when the user drops the cat on a
    /// different window. UserInfo:
    ///   - "pid":      Int32 — owner pid of dropped-on window
    ///   - "windowID": UInt32 — CGWindowID of dropped-on window
    static let catRebindRequested = Notification.Name("hangCat.rebindRequested")
}
