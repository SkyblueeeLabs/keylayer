import SwiftUI
import ServiceManagement
import Cocoa

// KeyLayerApp.swift — 菜单栏常驻 App 入口
// 编译：swiftc -O KeyLayerCore.swift KeyLayerApp.swift -o KeyLayer.app/Contents/MacOS/KeyLayer
// 采用 NSStatusItem + 自定义无边框面板（承载 SwiftUI 视图）。
// 不用 NSPopover：它的自动定位与尺寸缓存会导致「离图标很远」和「顶部被裁」。

func uiLog(_ s: String) {
    let url = Bundle.main.bundleURL
        .deletingLastPathComponent()
        .appendingPathComponent("KeyLayer.runtime.log")
    let line = "\(Date()) \(s)\n"
    guard let data = line.data(using: .utf8) else { return }
    if let h = FileHandle(forWritingAtPath: url.path) {
        h.seekToEndOfFile()
        h.write(data)
        h.closeFile()
    } else {
        try? data.write(to: url)
    }
}

@main
struct KeyLayerApp {
    static func main() {
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            let delegate = AppDelegate()
            app.delegate = delegate
            app.setActivationPolicy(.accessory)
            uiLog("main: NSApplication 启动")
            app.run()
        }
    }
}

final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var statusItem: NSStatusItem!
    var panel: KeyPanel!
    var hosting: NSHostingView<AnyView>!
    var manager: TapManager!
    var lastResign = Date.distantPast

    func applicationDidFinishLaunching(_ notification: Notification) {
        uiLog("applicationDidFinishLaunching")
        manager = TapManager()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = manager.enabled ? "KL" : "KL 关"
            let icon = NSImage(named: "MenuIcon")
                ?? NSImage(systemSymbolName: "keyboard", accessibilityDescription: "KeyLayer")
            icon?.isTemplate = true
            button.image = icon
            button.imagePosition = .imageLeading
            button.action = #selector(togglePanel(_:))
            button.target = self
            uiLog("状态项已创建 title=\(button.title)")
        } else {
            uiLog("[错误] 状态项 button 为 nil")
        }

        hosting = NSHostingView(rootView: AnyView(ContentView().environmentObject(manager)))
        hosting.frame = NSRect(x: 0, y: 0, width: Tokens.panelWidth, height: 10)
        hosting.layoutSubtreeIfNeeded()

        let size = panelSize()
        panel = KeyPanel(contentRect: NSRect(origin: .zero, size: size),
                         styleMask: [.borderless],
                         backing: .buffered,
                         defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.contentView = hosting
        hosting.frame = panel.contentView!.bounds
        hosting.autoresizingMask = [.width, .height]

        manager.onEnabledChange = { [weak self] enabled in
            self?.statusItem.button?.title = enabled ? "KL" : "KL 关"
            uiLog("开关切换为 \(enabled ? "启用" : "停用")")
        }

        // 启动后自动展示一次界面，确保 LSUIElement App 不「打开了却什么也看不到」
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.showPanel()
            uiLog("启动后自动展示界面")
        }

        // 调试用：KEYLAYER_SNAPSHOT=/path.png 时把界面渲染成图片，便于无窗口环境下检查布局
        if let path = ProcessInfo.processInfo.environment["KEYLAYER_SNAPSHOT"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
                guard let self = self else { return }
                self.hosting.layoutSubtreeIfNeeded()
                if let rep = self.hosting.bitmapImageRepForCachingDisplay(in: self.hosting.bounds) {
                    self.hosting.cacheDisplay(in: self.hosting.bounds, to: rep)
                    if let d = rep.representation(using: .png, properties: [:]) {
                        try? d.write(to: URL(fileURLWithPath: path))
                    }
                }
                uiLog("snapshot \(path) size=\(Int(self.hosting.bounds.width))x\(Int(self.hosting.bounds.height))")
            }
        }

        // 未授权时主动弹一次系统授权对话框，让 App 自动进入权限列表
        if !manager.tapOK, ProcessInfo.processInfo.environment["KEYLAYER_SNAPSHOT"] == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self = self, !self.manager.tapOK else { return }
                self.manager.requestAccessibility()
            }
        }
    }

    @objc func togglePanel(_ sender: Any?) {
        uiLog("状态项被点击")
        if panel.isVisible {
            panel.orderOut(nil)
        } else if Date().timeIntervalSince(lastResign) > 0.25 {
            showPanel()
        }
    }

    func panelSize() -> NSSize {
        // 宽度固定，按 SwiftUI 实际内容测高；+2 吸收取整误差，避免顶部被裁
        hosting.frame = NSRect(x: 0, y: 0, width: Tokens.panelWidth, height: 10)
        hosting.layoutSubtreeIfNeeded()
        let measured = hosting.fittingSize.height
        let height = min(700, max(240, ceil(measured) + 2))
        uiLog("panelSize measured=\(Int(measured)) -> \(Int(height))")
        return NSSize(width: Tokens.panelWidth, height: height)
    }

    func showPanel() {
        guard let button = statusItem.button, let win = button.window else { return }
        NSApp.activate(ignoringOtherApps: true)
        button.layoutSubtreeIfNeeded()

        let size = panelSize()
        panel.setContentSize(size)
        hosting.frame = panel.contentView!.bounds

        // 状态项按钮矩形换算到屏幕坐标，再贴着它下沿放置
        let inWindow = button.convert(button.bounds, to: nil)
        let anchor = win.convertToScreen(inWindow)
        let gap: CGFloat = 6
        var x = anchor.midX - size.width / 2
        var y = anchor.minY - size.height - gap
        if let screen = win.screen ?? NSScreen.main {
            let v = screen.visibleFrame
            x = min(max(x, v.minX + 8), v.maxX - size.width - 8)
            y = max(y, v.minY + 8)
        }
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.makeKeyAndOrderFront(nil)
        uiLog("panel 展示 anchor=\(anchor) frame=\(panel.frame)")
    }

    func windowDidResignKey(_ notification: Notification) {
        lastResign = Date()
        panel?.orderOut(nil)
    }
}

final class TapManager: ObservableObject {
    @Published var enabled: Bool
    @Published var trusted = AXIsProcessTrusted()
    @Published var loginEnabled = SMAppService.mainApp.status == .enabled
    @Published var loginError: String?
    @Published var tapOK = false
    var onEnabledChange: ((Bool) -> Void)?
    let tap = EventTap()

    init() {
        // 新键优先；旧键是改名前的状态，保留读取以免用户设置丢失
        let stored = UserDefaults.standard.object(forKey: "KeyLayerEnabled") as? Bool
            ?? UserDefaults.standard.object(forKey: "KeyMapEnabled") as? Bool
        enabled = stored ?? true
        tapOK = tap.install(debug: false, useSession: false, cmdOnly: false)
        tap.setEnabled(enabled)
        uiLog("TapManager init: enabled=\(enabled) tapOK=\(tapOK) trusted=\(trusted)")
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.trusted = AXIsProcessTrusted()
                // 以 CGEvent.tapCreate 的实际结果为准：macOS 27 把「辅助功能」
                // 改名为「设备控制与数据访问」后，AXIsProcessTrusted() 可能误报，
                // 不能让它卡住事件 tap 的创建。
                if !self.tapOK {
                    let ok = self.tap.install(debug: false, useSession: false, cmdOnly: false)
                    self.tapOK = ok
                    if ok {
                        self.tap.setEnabled(self.enabled)
                        uiLog("事件 tap 已建立，权限实际生效")
                    }
                }
            }
        }
    }

    func setEnabled(_ on: Bool) {
        enabled = on
        UserDefaults.standard.set(on, forKey: "KeyLayerEnabled")
        tap.setEnabled(on)
        onEnabledChange?(on)
    }

    func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        let granted = AXIsProcessTrustedWithOptions(options)
        uiLog("已弹出辅助功能授权请求, 当前=\(granted)")
    }

    func openAccessibility() {
        MainActor.assumeIsolated {
            if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(u)
            }
        }
    }

    func openInputMonitoring() {
        MainActor.assumeIsolated {
            if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                NSWorkspace.shared.open(u)
            }
        }
    }

    func setLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            loginError = nil
        } catch {
            loginEnabled = SMAppService.mainApp.status == .enabled
            loginError = "自动注册失败，请在 系统设置 → 通用 → 登录项 手动添加 KeyLayer"
        }
    }

    func quit() {
        MainActor.assumeIsolated { NSApplication.shared.terminate(nil) }
    }
}

struct ContentView: View {
    @EnvironmentObject var manager: TapManager

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.gap) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("KeyLayer").font(.headline)
                    Text("Windows 改键习惯 · macOS 复现").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $manager.enabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .onChange(of: manager.enabled) { _, newValue in
                        manager.setEnabled(newValue)
                    }
            }

            HStack(spacing: Tokens.capGap) {
                Circle()
                    .fill(manager.tapOK ? Tokens.statusOK : Tokens.statusWarn)
                    .frame(width: Tokens.dotSize, height: Tokens.dotSize)
                if manager.tapOK {
                    Text(statusText).font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(statusText).font(.caption).foregroundStyle(Tokens.statusWarn)
                }
            }

            if !manager.tapOK {
                VStack(alignment: .leading, spacing: 6) {
                    Button("请求系统授权") { manager.requestAccessibility() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    HStack(spacing: 8) {
                        Button("辅助功能") { manager.openAccessibility() }
                        Button("输入监控") { manager.openInputMonitoring() }
                    }
                    .font(.caption)
                    Text("授权后 2 秒内自动生效，无需重启")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }

            Divider()

            Text("按住 ⌥ 或 ⌘，再按下列键").font(.caption).foregroundStyle(.secondary)
            MapDiagram()

            Divider()

            HStack(spacing: 8) {
                Toggle("开机自启", isOn: $manager.loginEnabled)
                    .toggleStyle(.checkbox)
                    .onChange(of: manager.loginEnabled) { _, newValue in
                        manager.setLogin(newValue)
                    }
                Spacer()
                Button("退出") { manager.quit() }
            }
            .font(.caption)

            if let e = manager.loginError {
                Text(e).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(Tokens.panelPadding)
        .frame(width: Tokens.panelWidth, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: Tokens.panelRadius, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: Tokens.panelRadius, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
        )
    }

    private var statusText: String {
        if manager.tapOK {
            return manager.enabled ? "生效中 · 事件 tap 正常" : "已停用（开关关闭）"
        }
        return "事件 tap 未建立 — 请在设备控制与数据访问 / 输入监控中勾选 KeyLayer"
    }
}

struct MapDiagram: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.rowGap) {
            ForEach(Generated.keyCapRows.indices, id: \.self) { r in
                HStack(spacing: Tokens.capGap) {
                    ForEach(Generated.keyCapRows[r].indices, id: \.self) { c in
                        KeyCap(letter: Generated.keyCapRows[r][c].label,
                               action: Generated.keyCapRows[r][c].desc,
                               group: Generated.keyCapRows[r][c].group)
                    }
                }
            }
            Text("⇧ 保留选区 · 右⌃+B/G 打开网页 · VS Code 内 D 放行")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct KeyCap: View {
    let letter: String
    let action: String
    let group: String

    var body: some View {
        VStack(spacing: 3) {
            Text(letter)
                .font(.system(size: Tokens.bodySize, weight: .medium))
                .frame(width: Tokens.capKeyWidth, height: Tokens.capHeight)
                .background(RoundedRectangle(cornerRadius: Tokens.capRadius).fill(Tokens.groupSoft(group)))
                .overlay(RoundedRectangle(cornerRadius: Tokens.capRadius)
                    .stroke(Tokens.groupAccent(group).opacity(0.45), lineWidth: 0.8))
            Text(action)
                .font(.system(size: Tokens.microSize))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: Tokens.capWidth)
    }
}
