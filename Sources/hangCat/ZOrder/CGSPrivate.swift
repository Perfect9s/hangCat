import AppKit
import ApplicationServices

/// Wrappers for the SkyLight private window-server functions and the
/// undocumented `_AXUIElementGetWindow` we need to glue AX → CGWindowID.
///
/// All symbols are loaded lazily via `dlsym`; if any future macOS removes
/// or renames them, `isAvailable` returns false and callers must fall back.
enum CGSPrivate {
    typealias CGSConnectionID = Int32

    private typealias CGSMainConnectionFn =
        @convention(c) () -> CGSConnectionID
    private typealias CGSOrderWindowFn =
        @convention(c) (CGSConnectionID, CGWindowID, Int32, CGWindowID) -> CGError
    private typealias AXGetWindowFn =
        @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

    private static let handle: UnsafeMutableRawPointer? = dlopen(nil, RTLD_LAZY)

    private static func load<T>(_ symbol: String, as _: T.Type) -> T? {
        guard let handle, let sym = dlsym(handle, symbol) else { return nil }
        return unsafeBitCast(sym, to: T.self)
    }

    private static let _CGSMainConnectionID: CGSMainConnectionFn? =
        load("CGSMainConnectionID", as: CGSMainConnectionFn.self)
    private static let _CGSOrderWindow: CGSOrderWindowFn? =
        load("CGSOrderWindow", as: CGSOrderWindowFn.self)
    private static let _AXUIElementGetWindow: AXGetWindowFn? =
        load("_AXUIElementGetWindow", as: AXGetWindowFn.self)

    /// True when all required symbols resolved at startup.
    static let isAvailable: Bool =
        _CGSMainConnectionID != nil &&
        _CGSOrderWindow != nil &&
        _AXUIElementGetWindow != nil

    static var connectionID: CGSConnectionID {
        _CGSMainConnectionID?() ?? 0
    }

    /// Place `cat` immediately above `target` in the window server's z-order.
    /// `place` semantics: 1 = above, -1 = below, 0 = drop to bottom.
    @discardableResult
    static func orderAbove(cat: CGWindowID, target: CGWindowID) -> Bool {
        guard let fn = _CGSOrderWindow else { return false }
        return fn(connectionID, cat, 1, target) == .success
    }

    /// Resolve an AX window element to its CGWindowID via the private
    /// `_AXUIElementGetWindow` (no public alternative exists).
    static func windowID(of element: AXUIElement) -> CGWindowID? {
        guard let fn = _AXUIElementGetWindow else { return nil }
        var id: CGWindowID = 0
        return fn(element, &id) == .success ? id : nil
    }
}
