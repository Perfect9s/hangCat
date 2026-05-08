import AppKit

final class PetWindow: NSWindow {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // .floating keeps the cat reliably visible above the bound window.
        // We achieve the "stuck-to-window, gets-covered-when-target-is-covered"
        // visual via OcclusionMonitor (CGWindowListCopyWindowInfo) rather
        // than by manipulating absolute z-order with private SkyLight APIs,
        // since CGSOrderWindow's behaviour has shifted across macOS versions.
        level = .floating
        ignoresMouseEvents = false
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
            .stationary
        ]
        isExcludedFromWindowsMenu = true
        hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
