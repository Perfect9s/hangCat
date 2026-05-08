import AppKit
import ApplicationServices

// MARK: - Attribute reads

extension AXUIElement {
    func copyAttribute(_ name: String) -> AnyObject? {
        var value: AnyObject?
        let err = AXUIElementCopyAttributeValue(self, name as CFString, &value)
        return err == .success ? value : nil
    }

    func string(_ name: String) -> String? {
        copyAttribute(name) as? String
    }

    func bool(_ name: String) -> Bool? {
        (copyAttribute(name) as? NSNumber)?.boolValue
    }

    var role: String?    { string(kAXRoleAttribute) }
    var subrole: String? { string(kAXSubroleAttribute) }

    var position: CGPoint? {
        guard let v = copyAttribute(kAXPositionAttribute) else { return nil }
        var p = CGPoint.zero
        AXValueGetValue(v as! AXValue, .cgPoint, &p)
        return p
    }

    var size: CGSize? {
        guard let v = copyAttribute(kAXSizeAttribute) else { return nil }
        var s = CGSize.zero
        AXValueGetValue(v as! AXValue, .cgSize, &s)
        return s
    }

    /// Frame in AX (CG) coordinates: top-left origin of the primary display, Y grows down.
    var axFrame: CGRect? {
        guard let p = position, let s = size else { return nil }
        return CGRect(origin: p, size: s)
    }

    var isFullscreen: Bool {
        bool("AXFullScreen") ?? false
    }

    var isMinimized: Bool {
        bool(kAXMinimizedAttribute) ?? false
    }

    /// For an AXUIElement representing an application, returns its focused window (if any).
    var focusedWindow: AXUIElement? {
        guard let v = copyAttribute(kAXFocusedWindowAttribute) else { return nil }
        return (v as! AXUIElement)
    }
}

// MARK: - Coordinate conversion

enum AXCoords {
    /// The display that holds the menu bar. AX/CG coordinates are anchored
    /// to the top-left of *this* screen, regardless of multi-monitor layout.
    /// In Cocoa coords the menu-bar screen is always at origin (0, 0).
    static var primaryScreen: NSScreen? {
        NSScreen.screens.first(where: { $0.frame.origin == .zero })
            ?? NSScreen.screens.first
    }

    /// Height of the menu-bar-bearing screen, used as the Y-flip pivot when
    /// converting between CG (top-left origin) and Cocoa (bottom-left origin).
    static var primaryScreenHeight: CGFloat {
        primaryScreen?.frame.height ?? (NSScreen.main?.frame.height ?? 1080)
    }

    /// Convert an AX/CG-coordinate rect (top-left origin) to Cocoa (bottom-left origin).
    static func cgToCocoa(_ rect: CGRect) -> CGRect {
        let h = primaryScreenHeight
        return CGRect(
            x: rect.origin.x,
            y: h - rect.origin.y - rect.size.height,
            width: rect.size.width,
            height: rect.size.height
        )
    }

    /// Convert an AX/CG point to Cocoa.
    static func cgToCocoa(point: CGPoint) -> NSPoint {
        NSPoint(x: point.x, y: primaryScreenHeight - point.y)
    }

    /// Convert a Cocoa point to AX/CG (top-left origin).
    static func cocoaToCG(point: NSPoint) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreenHeight - point.y)
    }
}
