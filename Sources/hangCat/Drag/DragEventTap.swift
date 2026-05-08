import AppKit
import CoreGraphics

/// A passive global mouse event tap. Forwards leftMouseDown / Dragged / Up
/// to the supplied callbacks (on the main thread) without modifying the
/// event stream. Requires Accessibility permission (already obtained for AX).
///
/// Used by PetWindowController to do zero-latency cat-following while the
/// user drags a target window: AX notifications can lag a few frames during
/// fast drags, so we mirror the mouse delta in real time.
final class DragEventTap {
    var onMouseDown: ((CGPoint) -> Void)?
    var onMouseDragged: ((CGPoint) -> Void)?
    var onMouseUp: ((CGPoint) -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    @discardableResult
    func start() -> Bool {
        let mask: CGEventMask =
              (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.leftMouseDragged.rawValue)
            | (1 << CGEventType.leftMouseUp.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: DragEventTap.eventCallback,
            userInfo: refcon
        ) else {
            return false
        }
        self.tap = tap

        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        self.runLoopSource = src
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        runLoopSource = nil
        tap = nil
    }

    deinit { stop() }

    private static let eventCallback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else { return Unmanaged.passUnretained(event) }
        let owner = Unmanaged<DragEventTap>.fromOpaque(refcon).takeUnretainedValue()
        let location = event.location
        DispatchQueue.main.async {
            switch type {
            case .leftMouseDown:    owner.onMouseDown?(location)
            case .leftMouseDragged: owner.onMouseDragged?(location)
            case .leftMouseUp:      owner.onMouseUp?(location)
            default: break
            }
        }
        return Unmanaged.passUnretained(event)
    }
}
