import AppKit
import Foundation

enum CatImage {
    /// Native pixel dimensions (both images share these dimensions).
    static let nativeSize = NSSize(width: 1024, height: 1536)
    static var aspectRatio: CGFloat { nativeSize.width / nativeSize.height }

    /// Fraction of the draping image's height that is *body* (sits above the
    /// title bar). The remaining `1 - drapingBodyRatio` is the dangling head
    /// + paws that drape over the title bar onto the window content.
    /// Tuned visually for the current art — lowering this makes the cat
    /// sit lower on screen (more of the image hangs over the title bar).
    static let drapingBodyRatio: CGFloat = 0.33

    /// Cat draped over a window edge — head + paws hanging down. Used when idle on a window.
    static let draping: NSImage = load("cat_draping")

    /// Full-body cat in mid-air pose. Used when the user is dragging the cat.
    static let full: NSImage = load("cat_full")

    private static func load(_ name: String) -> NSImage {
        guard
            let url = Bundle.module.url(forResource: name, withExtension: "png"),
            let img = NSImage(contentsOf: url)
        else {
            assertionFailure("\(name).png missing from bundle")
            return NSImage(size: .init(width: 1, height: 1))
        }
        return img
    }
}
