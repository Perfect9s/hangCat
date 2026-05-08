import AppKit

/// Tracks whichever app is frontmost. Whenever the frontmost app changes,
/// it tears down the previous AXWindowTracker and spins up a new one for
/// the new app. The latest binding is forwarded via `onBindingChanged`.
///
/// Apps the cat should *not* attach to (Finder desktop, our own app, the
/// system UI helpers, etc.) are filtered here.
final class FrontmostAppObserver {
    var onBindingChanged: ((WindowBinding?) -> Void)?

    private var currentTracker: AXWindowTracker?
    private var workspaceObservers: [NSObjectProtocol] = []

    private static let blockedBundleIDs: Set<String> = [
        "com.apple.finder",
        "com.apple.dock",
        "com.apple.systemuiserver",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.WindowManager",
        "com.apple.loginwindow"
    ]

    func start() {
        let nc = NSWorkspace.shared.notificationCenter
        let activated = nc.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.bind(to: app)
        }
        workspaceObservers.append(activated)

        // Space switches don't always change the frontmost app, but the
        // *focused window* of that app may change (e.g., user swipes to a
        // Space showing a different window of the same app). Re-bind so we
        // re-attach AX observers to the right window.
        let spaceChanged = nc.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            if let app = NSWorkspace.shared.frontmostApplication {
                self?.bind(to: app)
            }
        }
        workspaceObservers.append(spaceChanged)

        if let app = NSWorkspace.shared.frontmostApplication {
            bind(to: app)
        }
    }

    func stop() {
        let nc = NSWorkspace.shared.notificationCenter
        for token in workspaceObservers { nc.removeObserver(token) }
        workspaceObservers.removeAll()
        currentTracker = nil
    }

    private func bind(to app: NSRunningApplication) {
        if app.processIdentifier == ProcessInfo.processInfo.processIdentifier { return }
        if let bid = app.bundleIdentifier, Self.blockedBundleIDs.contains(bid) {
            currentTracker = nil
            onBindingChanged?(nil)
            return
        }
        let pid = app.processIdentifier
        let tracker = AXWindowTracker(pid: pid)
        tracker?.onBindingChanged = { [weak self] binding in
            self?.onBindingChanged?(binding)
        }
        currentTracker = tracker
        if tracker == nil {
            onBindingChanged?(nil)
        }
    }
}
