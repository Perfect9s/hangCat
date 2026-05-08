import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItemController?
    private var pet: PetWindowController?
    private var bindingManager: BindingManager?
    private var dragTap: DragEventTap?
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let bm = BindingManager()
        bindingManager = bm
        statusItem = StatusItemController(bindingManager: bm)

        let p = PetWindowController()
        p.show()
        pet = p

        bootstrapTracking()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Tracking bootstrap

    private func bootstrapTracking() {
        if AccessibilityGate.isTrusted {
            startTracking()
        } else {
            promptAndWaitForTrust()
        }
    }

    private func promptAndWaitForTrust() {
        AccessibilityGate.requestTrust()
        let alert = NSAlert()
        alert.messageText = "需要辅助功能权限"
        alert.informativeText = """
        hangCat 需要"辅助功能"权限来读取窗口位置，让小猫可以贴在窗口标题栏上。

        点击"打开系统设置"，把 hangCat 加入"隐私与安全 > 辅助功能"列表并打开开关。授权后小猫会自动开始跟随窗口。
        """
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")
        if alert.runModal() == .alertFirstButtonReturn {
            AccessibilityGate.openSystemSettings()
        }
        permissionTimer = AccessibilityGate.waitUntilTrusted { [weak self] in
            self?.startTracking()
        }
    }

    private func startTracking() {
        guard let bm = bindingManager else { return }
        bm.onBindingChanged = { [weak self] binding in
            self?.pet?.updateBinding(binding)
        }
        bm.start()

        let tap = DragEventTap()
        tap.onMouseDown    = { [weak self] in self?.pet?.handleGlobalMouseDown(at: $0) }
        tap.onMouseDragged = { [weak self] in self?.pet?.handleGlobalMouseDragged(at: $0) }
        tap.onMouseUp      = { [weak self] in self?.pet?.handleGlobalMouseUp(at: $0) }
        if !tap.start() {
            NSLog("hangCat: failed to install CGEventTap; drag will fall back to AX notifications")
        }
        dragTap = tap
    }
}
