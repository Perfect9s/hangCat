import AppKit
import Foundation

// MARK: - Cat size

enum CatSize: Int, CaseIterable {
    case small = 0
    case medium = 1
    case large = 2
    case extraLarge = 3

    var displayName: String {
        switch self {
        case .small:      return "小"
        case .medium:     return "中"
        case .large:      return "大"
        case .extraLarge: return "特大"
        }
    }

    /// Width in points. Height is derived from CatImage.aspectRatio.
    var width: CGFloat {
        switch self {
        case .small:      return 90
        case .medium:     return 130
        case .large:      return 180
        case .extraLarge: return 240
        }
    }

    var pointSize: NSSize {
        let h = width / CatImage.aspectRatio
        return NSSize(width: width, height: h)
    }
}

// MARK: - Binding mode

enum BindingMode: Int, CaseIterable {
    /// One cat that hops onto whichever app/window is frontmost.
    case frontmost = 0
    /// One cat fixed to a chosen window — frontmost changes do nothing.
    /// In pinned mode, dragging the cat onto another window re-pins to that window.
    case pinned = 1

    var displayName: String {
        switch self {
        case .frontmost: return "跟随最前台"
        case .pinned:    return "钉住一个窗口（拖到别的窗口可改）"
        }
    }
}

// MARK: - Settings

final class Settings {
    static let shared = Settings()

    private let sizeKey         = "hangCat.size"
    private let bindingModeKey  = "hangCat.bindingMode"
    private let pinnedPIDKey    = "hangCat.pinnedPID"
    private let pinnedWindowKey = "hangCat.pinnedWindowID"

    var size: CatSize {
        get {
            let raw = UserDefaults.standard.object(forKey: sizeKey) as? Int ?? CatSize.medium.rawValue
            return CatSize(rawValue: raw) ?? .medium
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: sizeKey)
            NotificationCenter.default.post(name: .catSizeChanged, object: nil)
        }
    }

    var bindingMode: BindingMode {
        get {
            let raw = UserDefaults.standard.object(forKey: bindingModeKey) as? Int ?? BindingMode.frontmost.rawValue
            return BindingMode(rawValue: raw) ?? .frontmost
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: bindingModeKey)
            NotificationCenter.default.post(name: .catBindingModeChanged, object: nil)
        }
    }

    /// (pid, windowID) of the pinned target. Only meaningful when
    /// `bindingMode == .pinned`. Cleared when the pinned window dies.
    var pinnedTarget: (pid: pid_t, windowID: CGWindowID)? {
        get {
            guard
                let pid = UserDefaults.standard.object(forKey: pinnedPIDKey) as? Int32,
                let id  = UserDefaults.standard.object(forKey: pinnedWindowKey) as? UInt32
            else { return nil }
            return (pid, id)
        }
        set {
            if let nv = newValue {
                UserDefaults.standard.set(nv.pid, forKey: pinnedPIDKey)
                UserDefaults.standard.set(nv.windowID, forKey: pinnedWindowKey)
            } else {
                UserDefaults.standard.removeObject(forKey: pinnedPIDKey)
                UserDefaults.standard.removeObject(forKey: pinnedWindowKey)
            }
        }
    }

    private init() {}
}

extension Notification.Name {
    static let catSizeChanged        = Notification.Name("hangCat.sizeChanged")
    static let catBindingModeChanged = Notification.Name("hangCat.bindingModeChanged")
}
