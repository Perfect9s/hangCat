import AppKit

final class StatusItemController {
    private let item: NSStatusItem
    private weak var bindingManager: BindingManager?

    private var sizeMenuItems: [NSMenuItem] = []
    private var modeMenuItems: [NSMenuItem] = []
    private var modeChangeToken: NSObjectProtocol?

    init(bindingManager: BindingManager) {
        self.bindingManager = bindingManager
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.title = "🐱"
            button.toolTip = "hangCat"
        }

        let menu = NSMenu()

        // ---- Binding mode submenu ----
        let modeHeader = NSMenuItem(title: "绑定模式", action: nil, keyEquivalent: "")
        let modeSubmenu = NSMenu()
        for mode in BindingMode.allCases {
            let mi = NSMenuItem(
                title: mode.displayName,
                action: #selector(setMode(_:)),
                keyEquivalent: ""
            )
            mi.target = self
            mi.tag = mode.rawValue
            modeSubmenu.addItem(mi)
            modeMenuItems.append(mi)
        }
        modeHeader.submenu = modeSubmenu
        menu.addItem(modeHeader)

        // ---- Size submenu ----
        let sizeHeader = NSMenuItem(title: "尺寸", action: nil, keyEquivalent: "")
        let sizeSubmenu = NSMenu()
        for size in CatSize.allCases {
            let mi = NSMenuItem(
                title: size.displayName,
                action: #selector(setSize(_:)),
                keyEquivalent: ""
            )
            mi.target = self
            mi.tag = size.rawValue
            sizeSubmenu.addItem(mi)
            sizeMenuItems.append(mi)
        }
        sizeHeader.submenu = sizeSubmenu
        menu.addItem(sizeHeader)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit hangCat", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        item.menu = menu

        refreshChecks()

        modeChangeToken = NotificationCenter.default.addObserver(
            forName: .catBindingModeChanged, object: nil, queue: .main
        ) { [weak self] _ in
            self?.refreshChecks()
        }
    }

    deinit {
        if let t = modeChangeToken { NotificationCenter.default.removeObserver(t) }
    }

    // MARK: - Actions

    @objc private func setSize(_ sender: NSMenuItem) {
        guard let chosen = CatSize(rawValue: sender.tag) else { return }
        Settings.shared.size = chosen
        refreshChecks()
    }

    @objc private func setMode(_ sender: NSMenuItem) {
        guard let chosen = BindingMode(rawValue: sender.tag) else { return }
        switch chosen {
        case .frontmost:
            Settings.shared.bindingMode = .frontmost
        case .pinned:
            // Capture the current frontmost window and pin to it.
            if let bm = bindingManager, !bm.pinCurrent() {
                let alert = NSAlert()
                alert.messageText = "暂时没法钉住"
                alert.informativeText = "当前没有可钉住的窗口。先把想钉住的窗口切到前台（让小猫贴上去），再选「钉住一个窗口」。钉住后可把小猫拖到别的窗口换钉住目标。"
                alert.alertStyle = .informational
                alert.runModal()
            }
        }
        // Note: the mode-changed notification will trigger refreshChecks().
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Menu state

    private func refreshChecks() {
        let currentSize = Settings.shared.size
        for mi in sizeMenuItems {
            mi.state = (mi.tag == currentSize.rawValue) ? .on : .off
        }
        let currentMode = Settings.shared.bindingMode
        for mi in modeMenuItems {
            mi.state = (mi.tag == currentMode.rawValue) ? .on : .off
        }
    }
}
