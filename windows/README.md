# KeyLayer for Windows（Tauri v2）

用 Tauri v2（Rust + WebView2）重写的 Windows 版，**按 `spec/keybindings.json` 的行为规格重建**，不是给原来的 `KeyMap.exe` 套壳。这样不再内嵌 GPLv2 的 AutoHotkey 解释器，可以干净地按 MIT 授权；托盘弹窗界面也能和 macOS 版保持同一套视觉。

> **状态：已编译、已打包、核心键位已在 Windows 11 真机验证**（Rust 1.99 / Tauri 2.12 / MSVC）。下文「真机验证记录」列出了实际测过的项；未自动化或仍需手动确认的项单独列出。

## 前置

- Windows 10/11 x64，WebView2 Runtime（Win11 通常已内置）
- Node.js 20+（仅用于 Tauri CLI）
- Rust stable + MSVC Build Tools（`rustup` 默认 toolchain）
- Tauri v2 的系统依赖：见 <https://v2.tauri.app/start/prerequisites/>

## 构建

```bash
cd windows
npm install
npm run dev        # 开发：Tauri 内置 dev server 直接读项目根 ui/，改 HTML 热重载
npm run build      # 产出 release exe + NSIS / MSI 安装包
npm run build -- --no-bundle   # 只编译 exe，不打包安装器（CI 用）
```

纯逻辑测试：

```bash
node spec/verify.mjs                 # 共享规格 40 项（Node 参考实现，跨平台）
cd windows/src-tauri && cargo test   # Rust 复用同一份 40 项用例 + 生成表检查
```

## 已实现

| 能力 | 实现位置 |
| --- | --- |
| 11 条 Alt 映射（方向 / 行首行尾 / 删整行 / 四向滚轮） | `src/hook.rs` + 生成的 `generated.rs` |
| 右 Alt → Shift（AHK 33 行） | `hook.rs`：吞掉 RAlt，合成 Shift 按下/抬起 |
| 右 Ctrl + B/G 打开网址（AHK 95-100 行） | `hook.rs`：`GetAsyncKeyState(VK_RCONTROL)` 区分左右 |
| VS Code 内 `Alt+D` 放行（AHK 63-68 行） | `hook.rs`：`GetForegroundWindow` + `QueryFullProcessImageNameW` |
| Alt+Shift 保留选区 | `hook.rs`：不重复注入已按下的 Shift |
| 托盘面板 | `lib.rs`：按托盘位置 / 显示器边界定位、失焦收起、点击防抖、透明无边框、按内容自适应高度 |
| 启用状态持久化 | `%APPDATA%\com.skyblueee.keylayer\state.json` |
| 开机自启 | 官方 `tauri-plugin-autostart`（HKCU Run） |
| 钩子失败自动重试 | `hook.rs` 安装循环 |

### 两个关键实现细节

1. **Alt 缓冲转发。** 直接把左 Alt 透传给目标应用会让它进入菜单模式，随后合成的 Home / 方向键会被菜单吃掉（记事本、WinForms 上都能复现）。现在左 Alt 先被钩子暂扣：
   - 命中映射：目标应用完全看不到 Alt，直接收到合成键；
   - 非映射组合（Alt+Tab、Alt+F4、白名单放行等）：放行前补发一次 Alt 按下，松开时再补 Alt 抬起；
   - 单独按 Alt：松开时补一次 Alt 轻点，保留系统菜单栏行为。

2. **扩展键标志。** `Home/End/方向键` 属于扩展键，注入时必须带 `KEYEVENTF_EXTENDEDKEY`；否则删整行只会删掉换行符，不会删掉整行。已用原生按键序列对照验证。

3. **托盘 Click 会发两次。** Windows 下 `TrayIconEvent::Click` 在按下和抬起时各发一次（`button_state` 区分）。只处理抬起，否则一次点击会把面板「打开又关掉」——表现为闪一下。另加 400ms 显示宽限期，避免点击托盘时系统短暂抢焦点导致误收起。

## 真机验证记录（2026-11-11）

| 用例 | 方法 | 结果 |
| --- | --- | --- |
| `Alt+U/O` 行首 / 行尾 | 记事本 + WinForms TextBox | 通过 |
| `Alt+I/K` 上 / 下 | 同上 | 通过 |
| `Alt+D` 删整行 | 同上，中间行 | 通过（含换行） |
| `Shift+Alt+U` 保留选区 | WinForms 选区宽度断言 | 通过（SEL=10,3） |
| 右 Alt + `1` → `!` | 记事本输入 | 通过 |
| 右 Ctrl + B 打开百度 | 注入右 Ctrl+B；日志 `open-url:baidu`，系统拉起 Chrome 新窗口 | 通过 |
| 右 Ctrl 左右区分 | `KEYLAYER_DEBUG_KEYS`：右 Ctrl+A 为 `[ctrl,rightCtrl]`，左 Ctrl+B 不含 `rightCtrl` | 通过 |
| `Alt+Tab` / `Alt+F4` | 记事本窗口切换 / 关闭 | 通过 |
| 托盘单击开 / 关 | 向 `tray_icon_app` 窗口回放 `WM_LBUTTONUP`：第一次显示并保持，第二次隐藏；单独 `WM_LBUTTONDOWN` 不切换 | 通过 |
| 面板开关关闭后不再映射 | 关闭开关后重放按键 + 日志 | 通过（无 action 记录） |
| 启用状态重启保留 | 关闭 → 重启 → UIA 读取开关 | 通过（`{"enabled":false}`） |
| 开机自启开 / 关 | UIA 点击 + 检查 HKCU Run | 通过（写入 / 删除 `KeyLayer` 值） |
| 共享用例 | `cargo test` / `npm run check` | 3/3、40/40 |

## 调试开关（仅本机测试用）

| 环境变量 | 作用 |
| --- | --- |
| `KEYLAYER_DEBUG_LOG=<路径>` | 把安装、Alt 状态、命中动作写到指定文件 |
| `KEYLAYER_DEBUG_KEYS=1` | 逐键记录 vk / 修饰键 / 动作（含放行），用于核对左右 Ctrl／Alt 与白名单 |
| `KEYLAYER_ALLOW_INJECTED=1` | 允许处理其他程序合成的按键，便于自动化回放（默认忽略，防递归/防误触） |
| `KEYLAYER_SHOW_PANEL=1` | 启动即显示面板，便于截图 / UI 自动化 |

本程序的合成事件都带 `dwExtraInfo` 标记，即使打开 `ALLOW_INJECTED` 也不会二次改写自己。

## 尚未覆盖 / 需要继续

| 项 | 说明 |
| --- | --- |
| 右 Ctrl+G 打开 Google | 与 B 共用同一段代码，仅 B 做了外部浏览器实测；Google 在部分地区不可达 |
| VS Code 运行时白名单 | 进程名获取已验证（日志显示 `Notepad.exe`），未在真实 VS Code 内逐键复测 |
| 失焦自动收起 | 依赖真实前台焦点，自动化环境拿不到可靠焦点；托盘开/关本身已回放验证，收起行为需手动点验 |
| 高完整性级别窗口 | 低级钩子对以管理员运行的前台窗口可能失效 |
| 多显示器 / 混合 DPI | 定位按物理坐标 + 当前显示器边界夹取；混合 DPI 下建议实机再点一次 |
| `Alt+H/Y` 在 VS Code 内 | 原脚本有 VS Code 分支，骨架仍一律映射为滚轮 |
| 代码签名 | 对外分发需要 Authenticode 证书，否则 SmartScreen 会拦 |

## 键位覆盖

完整对照见 `spec/keybindings.json` 的 `scriptCoverage`（16 条规则逐条标注 `status`）：

- **已复刻并接通**：`!i/k/j/l/u/o`、`!n/!m`、`!h/!y`（滚轮）、`$!d`（含 VS Code 白名单）、`RAlt::Shift`、`>^b/>^g`。
- **有意改了触发键**：原脚本 `^!`（Ctrl+Alt）做选中，改为 **Alt+Shift** 保留选区。
- **完全未复刻**：`CapsLock→Esc`（建议走系统修饰键设置）、F8 窗口置顶、F10、Alt+Tab 鼠标移动、Win 组合 4 条、`>^f` 复制翻译、热字符串 `:::tabc::`、中键手势、光标处输入法提示、`!h/!y` 的 VS Code 分支。

## 与 macOS 版的关系

- 两端共用 `spec/keybindings.json`：映射表、动作语义、应用白名单、40 项回归用例。
- `spec/verify.mjs` 是可执行参考实现；Rust 与 Swift 都应与之对齐。
- 界面 `ui/index.html` 复刻了 macOS 版的键帽网格与配色（蓝＝方向、橙＝动作、绿＝滚轮、紫＝修饰键）。
- macOS 版是已完成并实测的参考；Windows 版的合成事件、菜单模式、DPI 等平台差异已在上文单独处理。

## 授权

`windows/` 与 `spec/` 属于根目录 [MIT License](../LICENSE) 覆盖范围。本目录**不包含**任何 AutoHotkey 脚本代码或 `KeyMap.exe` 二进制；实现是按行为规格重新编写的。历史文件的授权状态见 [`original/README.md`](../original/README.md)。
