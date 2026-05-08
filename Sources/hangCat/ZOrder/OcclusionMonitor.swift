import AppKit
import CoreGraphics

/// Decides whether the cat should currently be hidden. Two reasons to hide:
///
///   1. The bound target is **not on the current Space** — its frame still
///      has valid coordinates from AX, but the window is on a different
///      Space; we don't want a ghost cat at that position on this Space.
///   2. Another non-system, non-target-app window is **covering the title-bar
///      strip** of the bound target — the user is working with that
///      front-most window, the cat would just be in the way.
///
/// The single boolean result (`onOcclusionChanged(true)` ⇒ hide) is fed into
/// PetWindowController's visibility logic.
final class OcclusionMonitor {
    var onOcclusionChanged: ((Bool) -> Void)?

    /// Window IDs to ignore (e.g. our own cat window) in addition to the
    /// blanket same-PID filter.
    var ignoredWindowIDs: Set<CGWindowID> = []

    private static let ignoredOwnerNames: Set<String> = [
        "Window Server", "WindowServer",
        "Dock",
        "WindowManager",
        "Control Center", "ControlCenter",
        "Spotlight",
        "NotificationCenter",
        "SystemUIServer",
        "TextInputMenuAgent"
    ]

    private let occlusionStripHeight: CGFloat = 40

    private var timer: Timer?
    private var spaceChangeToken: NSObjectProtocol?
    private var binding: WindowBinding?
    private var lastOccluded = false

    func setBinding(_ binding: WindowBinding?) {
        self.binding = binding
        evaluate()
    }

    func start() {
        timer?.invalidate()
        let t = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.evaluate()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        // React immediately to Space switches — otherwise we'd wait up to
        // 0.5s before the cat hides on the new Space.
        spaceChangeToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.evaluate()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let t = spaceChangeToken {
            NSWorkspace.shared.notificationCenter.removeObserver(t)
        }
        spaceChangeToken = nil
    }

    deinit { stop() }

    func poke() { evaluate() }

    private func evaluate() {
        let occluded = computeOcclusion()
        if occluded != lastOccluded {
            lastOccluded = occluded
            onOcclusionChanged?(occluded)
        }
    }

    private func computeOcclusion() -> Bool {
        guard let binding else { return false }
        guard let targetID = binding.windowID, targetID != 0 else { return false }

        // (1) If the target window isn't on the current Space, hide.
        if !isOnCurrentSpace(targetID) {
            return true
        }

        // (2) Look for any qualifying non-target window above it that
        // overlaps the title-bar strip.
        let opts: CGWindowListOption = [.optionOnScreenAboveWindow]
        guard let info = CGWindowListCopyWindowInfo(opts, targetID) as? [[String: Any]] else {
            return false
        }

        let stripCocoa = NSRect(
            x: binding.frame.minX,
            y: binding.frame.maxY - occlusionStripHeight,
            width: binding.frame.width,
            height: occlusionStripHeight
        )

        let ourPID = ProcessInfo.processInfo.processIdentifier

        for w in info {
            let layer = (w[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            if layer != 0 { continue }

            if let id = w[kCGWindowNumber as String] as? UInt32,
               ignoredWindowIDs.contains(id) { continue }

            if let wpid = w[kCGWindowOwnerPID as String] as? Int32, wpid == ourPID { continue }
            if let wpid = w[kCGWindowOwnerPID as String] as? Int32, wpid == binding.pid { continue }

            let owner = w[kCGWindowOwnerName as String] as? String ?? ""
            if Self.ignoredOwnerNames.contains(owner) { continue }

            guard let bounds = w[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
            let cgRect = CGRect(
                x: bounds["X"] ?? 0,
                y: bounds["Y"] ?? 0,
                width: bounds["Width"] ?? 0,
                height: bounds["Height"] ?? 0
            )
            if cgRect.size.width < 100 || cgRect.size.height < 40 { continue }

            let cocoaRect = AXCoords.cgToCocoa(cgRect)
            if cocoaRect.intersects(stripCocoa) {
                return true
            }
        }
        return false
    }

    /// `CGWindowListCopyWindowInfo([.optionOnScreenOnly], …)` only returns
    /// windows on the current Space, so a missing windowID means the target
    /// has slid off to another Space (or been minimized / closed).
    private func isOnCurrentSpace(_ windowID: CGWindowID) -> Bool {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return true   // can't tell → assume yes, default to "show"
        }
        for w in info {
            if let id = w[kCGWindowNumber as String] as? UInt32, id == windowID {
                return true
            }
        }
        return false
    }
}
