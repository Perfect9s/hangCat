import AppKit
import SwiftUI

final class PetWindowController: NSWindowController {
    private let viewModel = PetViewModel()
    private var sizeObserverToken: NSObjectProtocol?

    /// Most recently reported binding. Nil when no suitable window is bound.
    private var binding: WindowBinding?

    /// User-applied offset from the default centered position on the title
    /// bar. Updated when the user drops the cat anywhere along the title
    /// bar; reset to .zero when the binding switches to a different windowID
    /// (so each new window starts with the cat at title-bar center).
    private var userOffset: NSPoint = .zero

    /// If non-nil when the next binding update arrives with a *different*
    /// windowID, this offset is adopted (instead of being reset to .zero).
    /// Used by the drag-to-rebind flow so the cat lands exactly where the
    /// user dropped it on the new window.
    private var pendingRebindOffset: NSPoint?

    /// Set while the user is actively dragging the cat itself.
    private var userIsDragging = false

    /// Set while we're mirroring a window-drag from the global event tap.
    private var followAnchor: (mouseCG: CGPoint, catOrigin: NSPoint)?

    private let titleBarHeightHint: CGFloat = 32

    private var isOccluded = false
    private let occlusion = OcclusionMonitor()

    /// True while the click-to-fly animation is running. Suppresses
    /// AX-driven repositioning so the animation stays smooth.
    private var isAnimating = false

    /// How far the cat slides on a single click (in points, before clamping).
    private let flyDistance: CGFloat = 110
    /// Animation duration for the fly-off.
    private let flyDuration: CFTimeInterval = 0.32

    convenience init() {
        let initialSize = Settings.shared.size.pointSize
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(
            x: screenFrame.midX - initialSize.width / 2,
            y: screenFrame.maxY - initialSize.height - 80
        )
        let window = PetWindow(contentRect: NSRect(origin: origin, size: initialSize))
        window.alphaValue = 0

        self.init(window: window)
        installContainer(in: window, size: initialSize)

        sizeObserverToken = NotificationCenter.default.addObserver(
            forName: .catSizeChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applySize()
        }

        occlusion.ignoredWindowIDs = [CGWindowID(window.windowNumber)]
        occlusion.onOcclusionChanged = { [weak self] occluded in
            self?.isOccluded = occluded
            self?.updateVisibility()
        }
        occlusion.start()
    }

    deinit {
        if let token = sizeObserverToken { NotificationCenter.default.removeObserver(token) }
    }

    func show() {
        window?.orderFrontRegardless()
        if let window {
            occlusion.ignoredWindowIDs = [CGWindowID(window.windowNumber)]
        }
    }

    // MARK: - External inputs

    func updateBinding(_ binding: WindowBinding?) {
        let oldID = self.binding?.windowID
        self.binding = binding
        let newID = binding?.windowID

        // Resolve offset for the new window.
        if oldID != newID {
            if let pending = pendingRebindOffset {
                // Drag-to-rebind landing: the offset was computed against
                // the new target before we triggered the rebind.
                userOffset = pending
                pendingRebindOffset = nil
            } else {
                // Plain binding change (e.g. frontmost app switched) —
                // start fresh at title-bar center on the new window.
                userOffset = .zero
            }
        }

        if followAnchor == nil {
            repositionToBinding()
        }
        occlusion.setBinding(binding)
        updateVisibility()
    }

    // MARK: - Global mouse events (from DragEventTap)

    func handleGlobalMouseDown(at cg: CGPoint) {
        if userIsDragging { return }
        guard let bound = binding?.frame, let window else { return }

        let cocoaPoint = AXCoords.cgToCocoa(point: cg)
        if window.frame.contains(cocoaPoint) { return } // clicks on cat → PetContainerView

        let titleBarRect = NSRect(
            x: bound.minX,
            y: bound.maxY - titleBarHeightHint,
            width: bound.width,
            height: titleBarHeightHint
        )
        guard titleBarRect.contains(cocoaPoint) else { return }

        followAnchor = (mouseCG: cg, catOrigin: window.frame.origin)
    }

    func handleGlobalMouseDragged(at cg: CGPoint) {
        guard let anchor = followAnchor, let window else { return }
        let dx = cg.x - anchor.mouseCG.x
        let dy = -(cg.y - anchor.mouseCG.y)   // CG-Y → Cocoa-Y
        window.setFrameOrigin(NSPoint(
            x: anchor.catOrigin.x + dx,
            y: anchor.catOrigin.y + dy
        ))
    }

    func handleGlobalMouseUp(at cg: CGPoint) {
        guard followAnchor != nil else { return }
        followAnchor = nil
        repositionToBinding()
        occlusion.poke()
    }

    // MARK: - Container view

    private func installContainer(in window: NSWindow, size: NSSize) {
        let container = PetContainerView(frame: NSRect(origin: .zero, size: size))
        container.autoresizingMask = [.width, .height]
        container.onDragChanged = { [weak self] dragging in
            self?.handleSelfDragChanged(dragging)
        }
        container.onClicked = { [weak self] localPoint in
            self?.handleSelfClicked(at: localPoint)
        }

        let host = NSHostingView(rootView: PetView(viewModel: viewModel))
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)

        window.contentView = container
    }

    private func handleSelfDragChanged(_ dragging: Bool) {
        userIsDragging = dragging
        viewModel.pose = dragging ? .dragging : .idle
        if !dragging {
            processDrop()
            occlusion.poke()
        }
        updateVisibility()
    }

    /// Single-click on the cat → "swat away": cat slides along the title bar
    /// in the direction opposite the click, settles at a new offset.
    /// `localPoint` is in the cat window's local coords (origin bottom-left).
    private func handleSelfClicked(at localPoint: NSPoint) {
        guard !isAnimating, !userIsDragging else { return }
        guard let window, let bound = binding?.frame else { return }

        let size = window.frame.size

        // Click on right half of cat → fly left; click on left half → fly right.
        let centerX = size.width / 2
        let direction: CGFloat = (localPoint.x > centerX) ? -1 : 1

        // Clamp final offset so the cat stays mostly within the title bar
        // (allow about a quarter of the cat's width to peek past the edges).
        let maxOffsetX = max(0, bound.width / 2 - size.width / 4)
        let proposed = userOffset.x + direction * flyDistance
        let newOffsetX = max(-maxOffsetX, min(maxOffsetX, proposed))

        let dangle = size.height * (1 - CatImage.drapingBodyRatio)
        let newFrame = NSRect(
            x: bound.midX - size.width / 2 + newOffsetX,
            y: bound.maxY - dangle,
            width: size.width,
            height: size.height
        )

        isAnimating = true
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = flyDuration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(newFrame, display: true)
        }, completionHandler: { [weak self] in
            self?.userOffset.x = newOffsetX
            self?.isAnimating = false
        })
    }

    // MARK: - Drop handling

    /// Called when the user releases a self-drag. Decides whether to:
    /// (a) re-pin onto a different window (in pinned mode), or
    /// (b) save the new offset against the current binding.
    private func processDrop() {
        guard let window else { return }
        let catFrame = window.frame
        let dropCenter = NSPoint(x: catFrame.midX, y: catFrame.midY)
        let cgPoint = AXCoords.cocoaToCG(point: dropCenter)

        // Drag-to-rebind only makes sense in pinned mode.
        if Settings.shared.bindingMode == .pinned,
           let hit = WindowResolver.findWindow(
                under: cgPoint,
                excludingPID: ProcessInfo.processInfo.processIdentifier),
           hit.windowID != binding?.windowID
        {
            // Compute the offset against the new target's frame *before*
            // requesting the rebind, so the cat lands at exactly the drop
            // position when the new binding arrives.
            let newTargetCocoa = AXCoords.cgToCocoa(hit.cgBounds)
            pendingRebindOffset = computeOffset(
                catOrigin: catFrame.origin,
                target: newTargetCocoa,
                size: catFrame.size
            )
            NotificationCenter.default.post(
                name: .catRebindRequested,
                object: nil,
                userInfo: [
                    "pid": hit.pid,
                    "windowID": hit.windowID
                ]
            )
            return
        }

        // Same window (or no qualifying drop target) — save offset against
        // current binding so the cat stays where the user put it.
        if let bound = binding?.frame {
            userOffset = computeOffset(
                catOrigin: catFrame.origin,
                target: bound,
                size: catFrame.size
            )
            repositionToBinding()
        }
    }

    /// We only preserve the **horizontal** offset; vertical position always
    /// snaps back to the title-bar contact line (drapingBodyRatio).
    /// Effectively: the cat slides freely along the title bar but can't
    /// drift up or down.
    private func computeOffset(catOrigin: NSPoint, target: CGRect, size: NSSize) -> NSPoint {
        let defaultX = target.midX - size.width / 2
        return NSPoint(x: catOrigin.x - defaultX, y: 0)
    }

    // MARK: - Layout

    private func applySize() {
        guard let window else { return }
        let newSize = Settings.shared.size.pointSize
        if let bound = binding?.frame, !userIsDragging {
            window.setFrame(catFrame(over: bound, size: newSize), display: true, animate: false)
        } else {
            let oldFrame = window.frame
            let newOrigin = NSPoint(x: oldFrame.origin.x, y: oldFrame.maxY - newSize.height)
            window.setFrame(NSRect(origin: newOrigin, size: newSize), display: true, animate: false)
        }
    }

    private func repositionToBinding() {
        guard let window, let bound = binding?.frame, !userIsDragging, !isAnimating else { return }
        let size = window.frame.size
        window.setFrame(catFrame(over: bound, size: size), display: true, animate: false)
    }

    /// Default centered position (body on title bar, head + paws dangling)
    /// PLUS the user's saved offset.
    private func catFrame(over target: CGRect, size: NSSize) -> NSRect {
        let dangle = size.height * (1 - CatImage.drapingBodyRatio)
        let originX = target.midX - size.width / 2 + userOffset.x
        let originY = target.maxY - dangle           + userOffset.y
        return NSRect(x: originX, y: originY, width: size.width, height: size.height)
    }

    // MARK: - Visibility

    private func updateVisibility() {
        if userIsDragging {
            window?.alphaValue = 1
            return
        }
        if binding == nil {
            window?.alphaValue = 0
            return
        }
        window?.alphaValue = isOccluded ? 0 : 1
    }
}
