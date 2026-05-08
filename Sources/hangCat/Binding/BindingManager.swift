import AppKit
import ApplicationServices

/// Single point of orchestration for the binding modes.
/// Owns the trackers; pushes a `[id: WindowBinding]` snapshot into PetSwarm
/// whenever anything relevant changes.
///
/// Modes:
/// - `.frontmost`: one entry, key `"main"`, follows whichever app is frontmost
/// - `.pinned`:    one entry, key `"main"`, locked to a specific (pid, windowID).
///                 Drag-to-rebind is supported via `.catRebindRequested`.
final class BindingManager {
    var onBindingChanged: ((WindowBinding?) -> Void)?

    /// Owners we never bind to (system UI, our process, file manager, etc.)
    static let blockedOwnerNames: Set<String> = [
        "Finder", "Dock", "Window Server", "WindowServer",
        "Control Center", "ControlCenter", "Spotlight",
        "NotificationCenter", "Notification Center",
        "SystemUIServer", "WindowManager", "loginwindow"
    ]

    private var current: WindowBinding?

    private var frontmost: FrontmostAppObserver?
    private var pinnedTracker: AXWindowTracker?

    private var modeChangeToken: NSObjectProtocol?
    private var rebindRequestToken: NSObjectProtocol?

    // MARK: - Lifecycle

    func start() {
        modeChangeToken = NotificationCenter.default.addObserver(
            forName: .catBindingModeChanged, object: nil, queue: .main
        ) { [weak self] _ in
            self?.reload()
        }
        rebindRequestToken = NotificationCenter.default.addObserver(
            forName: .catRebindRequested, object: nil, queue: .main
        ) { [weak self] note in
            self?.handleRebindRequest(note)
        }
        applyMode()
    }

    func stop() {
        if let t = modeChangeToken { NotificationCenter.default.removeObserver(t) }
        if let t = rebindRequestToken { NotificationCenter.default.removeObserver(t) }
        modeChangeToken = nil
        rebindRequestToken = nil
        teardownTrackers()
    }

    deinit { stop() }

    // MARK: - Public actions (called from the menu)

    /// Capture the current frontmost binding and switch to pinned mode.
    /// Returns false if there is no current target to pin.
    @discardableResult
    func pinCurrent() -> Bool {
        guard let main = current, let id = main.windowID else { return false }
        Settings.shared.pinnedTarget = (main.pid, id)
        Settings.shared.bindingMode = .pinned
        return true
    }

    func unpin() {
        Settings.shared.pinnedTarget = nil
        Settings.shared.bindingMode = .frontmost
    }

    // MARK: - Rebind via drag-and-drop

    private func handleRebindRequest(_ note: Notification) {
        guard
            let pid = note.userInfo?["pid"] as? Int32,
            let windowID = note.userInfo?["windowID"] as? UInt32
        else { return }

        switch Settings.shared.bindingMode {
        case .frontmost:
            // In frontmost mode, dropping on another window means: bring that
            // window's app to the foreground so the cat naturally follows it.
            if let app = NSRunningApplication(processIdentifier: pid) {
                app.activate()
            }
            // Try to also raise the specific dropped-on window inside that app.
            if let ax = AXWindowFinder.find(pid: pid, windowID: windowID) {
                AXUIElementPerformAction(ax, kAXRaiseAction as CFString)
            }

        case .pinned:
            // Re-pin to the dropped-on window.
            Settings.shared.pinnedTarget = (pid, windowID)
            // Mode is already .pinned; setter won't trigger reload, force one.
            reload()
        }
    }

    // MARK: - Internals

    private func reload() {
        teardownTrackers()
        current = nil
        emit()
        applyMode()
    }

    private func teardownTrackers() {
        frontmost?.stop(); frontmost = nil
        pinnedTracker = nil
    }

    private func applyMode() {
        switch Settings.shared.bindingMode {
        case .frontmost: startFrontmost()
        case .pinned:    startPinned()
        }
    }

    private func startFrontmost() {
        let f = FrontmostAppObserver()
        f.onBindingChanged = { [weak self] binding in
            self?.update(binding: binding)
        }
        f.start()
        frontmost = f
    }

    private func startPinned() {
        guard let pinned = Settings.shared.pinnedTarget else {
            Settings.shared.bindingMode = .frontmost
            return
        }
        guard let axWindow = AXWindowFinder.find(pid: pinned.pid, windowID: pinned.windowID) else {
            Settings.shared.pinnedTarget = nil
            Settings.shared.bindingMode = .frontmost
            return
        }
        let tracker = AXWindowTracker(pid: pinned.pid, mode: .fixed(axWindow))
        tracker?.onBindingChanged = { [weak self] binding in
            self?.update(binding: binding)
            if binding == nil {
                Settings.shared.pinnedTarget = nil
                Settings.shared.bindingMode = .frontmost
            }
        }
        pinnedTracker = tracker
    }

    private func update(binding: WindowBinding?) {
        current = binding
        emit()
    }

    private func emit() {
        onBindingChanged?(current)
    }
}
