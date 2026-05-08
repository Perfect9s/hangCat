# hangCat

一只挂在 macOS 窗口标题栏上耷拉着的像素小猫。会跟着你正在用的窗口走、随窗口拖动而移动；挡住按钮的时候单击一下，它会自己沿着标题栏滑开。

[English](./README.md)

<p>
  <img src="Sources/hangCat/Resources/cat_draping.png" width="160" alt="耷拉在窗口上的小猫" />
  <img src="Sources/hangCat/Resources/cat_full.png" width="160" alt="被拎起来的全身猫" />
</p>

## 安装

1. 在 [最新 release](../../releases/latest) 下载 `hangCat.app.zip`
2. 解压后把 **hangCat.app** 拖到 `/Applications`
3. 首次打开会被 Gatekeeper 拦下来（因为没花钱做公证），任选一种解决：
   - 右键 `hangCat.app` → **打开** → **仍要打开**
   - 或者在终端跑一次：`xattr -dr com.apple.quarantine /Applications/hangCat.app`
4. 第一次启动会要求"辅助功能"权限（系统设置 → 隐私与安全 → 辅助功能），授权后小猫开始跟随窗口

## 功能

- **耷拉在标题栏上**：身体在标题栏上方，脑袋和爪子垂下来盖住窗口顶部一点点
- **拖动窗口零延迟跟随**：用 `CGEventTap` 实时镜像鼠标位移，基本看不到拖尾
- **单击拍飞**：单击小猫它会沿着标题栏滑开一段距离，露出底下被挡住的按钮 / 信息
- **长按拖动**：可以左右调整猫在标题栏上的位置，纵向会自动吸附回标题栏高度
- **两种绑定模式**（菜单栏 🐱 → 绑定模式）：
  - **跟随最前台**：哪个 app 在前台就贴哪个
  - **钉住一个窗口**：固定在某个窗口上不再跟前台变。**把猫拖到另一个窗口的标题栏松手，就改钉到那个窗口**
- **尺寸可调**（菜单栏 🐱 → 尺寸）：小 / 中 / 大 / 特大
- **自动隐藏**：目标窗口全屏、最小化、切到别的 Space、或被其他 app 的窗口盖住时，猫会自动隐藏

## 自己编译

```sh
git clone <你的 fork 地址> hangCat
cd hangCat
./scripts/make-app.sh         # 生成 hangCat.app 和 hangCat.app.zip
open hangCat.app
```

需要 Swift 5.9+、macOS 14+，无第三方依赖。

### 一键发版

```sh
./scripts/release.sh 0.2.0 "fix cat sometimes not appearing"
```

一条命令做完：编译 universal `.app` → 自动 commit → 打 `v0.2.0` tag → 推到 origin → 装了 `gh` 就直接创建/更新 GitHub release 并把 `build/hangCat.app.zip` 附上去；没装 `gh` 就给一个浏览器一键链接让你手动拖文件上传。

## 实现原理

| 关注点 | 方案 |
|---|---|
| 找到目标窗口 | `AXUIElementCreateApplication(pid)` + `AXObserver` 订阅 `kAXMovedNotification` / `kAXResizedNotification` / `kAXFocusedWindowChangedNotification` |
| 拖动丝滑跟随 | 全局 `CGEventTap` 监听 `leftMouseDown/Dragged/Up`，实时偏移猫窗口位置 |
| AX → CGWindowID | `_AXUIElementGetWindow`（私有 API，用 `dlsym` 加载；不可用时优雅降级） |
| 被盖住时隐藏 | `CGWindowListCopyWindowInfo(.optionOnScreenAboveWindow, targetID)` —— 公开 API，跨版本稳定 |
| 渲染 | SwiftUI `Image` + `.interpolation(.none)` 保留像素感 |

猫窗口固定在 `.floating` 级别（避免被各种 macOS 版本不一致的 z-order 私有 API 坑到），靠 `OcclusionMonitor` 检测到目标被遮挡时手动把猫隐藏，效果等价于"贴住目标窗口"。

## License

MIT（见 [LICENSE](./LICENSE)）。
