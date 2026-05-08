import AppKit

/// Hosts the SwiftUI cat and intercepts mouse events so we can:
///   - manually drive the window's frame during a drag
///   - distinguish click vs drag (with a small movement threshold)
///   - notify when a drag starts / ends so the cat sprite can swap pose
final class PetContainerView: NSView {
    var onDragChanged: ((Bool) -> Void)?
    /// Fired on mouse-up when the user clicked without exceeding the drag
    /// threshold. The point is in this view's local coordinate space.
    var onClicked: ((NSPoint) -> Void)?

    private var anchorMouse: NSPoint = .zero
    private var anchorWindowOrigin: NSPoint = .zero
    private var trackingDrag = false
    private let dragThreshold: CGFloat = 3

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Always handle mouse events at this layer; ignore any subview
        // (the SwiftUI hosting view) so a window drag can take over cleanly.
        return bounds.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        anchorMouse = NSEvent.mouseLocation
        anchorWindowOrigin = window?.frame.origin ?? .zero
        trackingDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        let cur = NSEvent.mouseLocation
        let dx = cur.x - anchorMouse.x
        let dy = cur.y - anchorMouse.y
        if !trackingDrag, hypot(dx, dy) > dragThreshold {
            trackingDrag = true
            onDragChanged?(true)
        }
        if trackingDrag, let win = window {
            win.setFrameOrigin(NSPoint(
                x: anchorWindowOrigin.x + dx,
                y: anchorWindowOrigin.y + dy
            ))
        }
    }

    override func mouseUp(with event: NSEvent) {
        if trackingDrag {
            onDragChanged?(false)
        } else {
            // No drag — fire as a click.
            let local = convert(event.locationInWindow, from: nil)
            onClicked?(local)
        }
        trackingDrag = false
    }
}
