import CoreGraphics

/// What the cat needs to know about the window it's currently attached to.
struct WindowBinding {
    /// Frame in Cocoa coordinates (Y up, primary-screen-origin).
    let frame: CGRect
    /// CGWindowID. `nil` if `_AXUIElementGetWindow` was unavailable; in that
    /// case the OcclusionMonitor degrades to "always show".
    let windowID: CGWindowID?
    /// Owner process of the bound window. Used so OcclusionMonitor can ignore
    /// the target app's own auxiliary windows (panels, sheets, side-panels).
    let pid: pid_t
}
