import AppKit
import ApplicationServices

/// Tracks a single window of one application via AXObserver.
///
/// Two modes:
/// - `.followFocused` (default): tracks whichever window is currently the
///   app's focused window; re-attaches when focus moves between windows.
/// - `.fixed(window)`: tracks one specific window only — when that window
///   dies the binding goes nil and stays nil.
///
/// `onBindingChanged` fires (on the main thread) on every relevant change.
/// Frames are reported in **Cocoa coordinates**.
final class AXWindowTracker {
    enum Mode {
        case followFocused
        case fixed(AXUIElement)
    }

    let pid: pid_t
    let appElement: AXUIElement
    /// Re-emits the current binding when assigned, so callers that set this
    /// after init still receive the initial value (otherwise the first
    /// `publish()` from init runs before the closure is hooked up).
    var onBindingChanged: ((WindowBinding?) -> Void)? {
        didSet { publish() }
    }

    private let mode: Mode
    private var observer: AXObserver?
    private var trackedWindow: AXUIElement?

    private static let appNotifications: [String] = [
        kAXFocusedWindowChangedNotification,
        kAXApplicationActivatedNotification,
        kAXApplicationDeactivatedNotification
    ]

    private static let windowNotifications: [String] = [
        kAXMovedNotification,
        kAXResizedNotification,
        kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification,
        kAXUIElementDestroyedNotification,
        "AXWindowMovedByUser",
        "AXWindowResizedByUser"
    ]

    convenience init?(pid: pid_t) {
        self.init(pid: pid, mode: .followFocused)
    }

    init?(pid: pid_t, mode: Mode) {
        self.pid = pid
        self.mode = mode
        self.appElement = AXUIElementCreateApplication(pid)

        guard setupObserver() else { return nil }

        switch mode {
        case .followFocused:
            attachAppNotifications()
            attachToFocusedWindow()
        case .fixed(let win):
            attachToWindow(win)
        }
        publish()
    }

    deinit { teardown() }

    // MARK: - Setup / teardown

    private func setupObserver() -> Bool {
        var obs: AXObserver?
        let err = AXObserverCreate(pid, AXWindowTracker.callback, &obs)
        guard err == .success, let obs else { return false }
        self.observer = obs
        let src = AXObserverGetRunLoopSource(obs)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
        return true
    }

    private func teardown() {
        detachFromCurrentWindow()
        if let obs = observer, case .followFocused = mode {
            for n in Self.appNotifications {
                AXObserverRemoveNotification(obs, appElement, n as CFString)
            }
        }
        if let obs = observer {
            let src = AXObserverGetRunLoopSource(obs)
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .defaultMode)
        }
        observer = nil
        trackedWindow = nil
    }

    private func attachAppNotifications() {
        guard let obs = observer else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for n in Self.appNotifications {
            AXObserverAddNotification(obs, appElement, n as CFString, refcon)
        }
    }

    private func attachToFocusedWindow() {
        detachFromCurrentWindow()
        guard let win = appElement.focusedWindow else {
            trackedWindow = nil
            return
        }
        attachToWindow(win)
    }

    private func attachToWindow(_ win: AXUIElement) {
        detachFromCurrentWindow()
        trackedWindow = win
        guard let obs = observer else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for n in Self.windowNotifications {
            AXObserverAddNotification(obs, win, n as CFString, refcon)
        }
    }

    private func detachFromCurrentWindow() {
        guard let obs = observer, let win = trackedWindow else { return }
        for n in Self.windowNotifications {
            AXObserverRemoveNotification(obs, win, n as CFString)
        }
        trackedWindow = nil
    }

    // MARK: - Notification dispatch

    private static let callback: AXObserverCallback = { _, element, notification, refcon in
        guard let refcon else { return }
        let tracker = Unmanaged<AXWindowTracker>.fromOpaque(refcon).takeUnretainedValue()
        let name = notification as String
        DispatchQueue.main.async {
            tracker.handle(element: element, notification: name)
        }
    }

    private func handle(element: AXUIElement, notification: String) {
        switch notification {
        case kAXFocusedWindowChangedNotification,
             kAXApplicationActivatedNotification:
            if case .followFocused = mode {
                attachToFocusedWindow()
                publish()
            }

        case kAXUIElementDestroyedNotification:
            if case .fixed = mode {
                // The pinned window is gone — emit nil and stay there.
                trackedWindow = nil
                publish()
            } else {
                attachToFocusedWindow()
                publish()
            }

        case kAXWindowMiniaturizedNotification,
             kAXWindowDeminiaturizedNotification:
            // Visibility may have changed; re-evaluate.
            publish()

        case kAXApplicationDeactivatedNotification:
            // Stay attached — position updates still come via window events.
            break

        default:
            // Move / resize / etc.
            publish()
        }
    }

    // MARK: - Output

    private func publish() {
        onBindingChanged?(currentBinding())
    }

    private func currentBinding() -> WindowBinding? {
        guard let win = trackedWindow else { return nil }
        if win.isMinimized || win.isFullscreen { return nil }
        guard let axRect = win.axFrame else { return nil }
        guard axRect.size.width > 50, axRect.size.height > 30 else { return nil }
        let cocoaFrame = AXCoords.cgToCocoa(axRect)
        let windowID = CGSPrivate.windowID(of: win)
        return WindowBinding(frame: cocoaFrame, windowID: windowID, pid: pid)
    }
}

// MARK: - Helpers for resolving an AXUIElement by CGWindowID

extension AXUIElement {
    /// All windows of an application, in AX-reported order.
    var windows: [AXUIElement] {
        guard let v = copyAttribute(kAXWindowsAttribute) else { return [] }
        return (v as? [AXUIElement]) ?? []
    }
}

enum AXWindowFinder {
    /// Find a specific window of an app by CGWindowID. Used to re-pin after
    /// a settings reload (we persist windowID, but AXUIElements are runtime).
    static func find(pid: pid_t, windowID: CGWindowID) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        for win in app.windows {
            if let id = CGSPrivate.windowID(of: win), id == windowID {
                return win
            }
        }
        return nil
    }
}
