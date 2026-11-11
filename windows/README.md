# KeyLayer for Windows（Tauri v2 骨架）

用 Tauri v2（Rust + WebView2）重写的 Windows 版，**按 `spec/keybindings.json` 的行为规格重建**，不是给原来的 `KeyMap.exe` 套壳。这样不再内嵌 GPLv2 的 AutoHotkey 解释器，可以干净地按 MIT 授权；托盘弹窗界面也能和 macOS 版保持同一套视觉。

> **状态：骨架 / 未验证。** 本项目在 macOS 上编写，Windows 专属部分（低级键盘钩子、托盘、窗口定位）**没有编译或运行验证**。请在 Windows 机器上按下面步骤构建，并按「首次构建检查清单」处理报错。

## 前置

- Windows 10/11 x64，WebView2 Runtime（Win11 通常已内置）
- Node.js 20+（仅用于 `npm run dev` 的静态服务和 Tauri CLI）
- Rust stable + MSVC Build Tools（`rustup` 默认 toolchain）
- Tauri v2 的系统依赖：见 <https://v2.tauri.app/start/prerequisites/>

## 构建

```bash
cd windows
npm install
npm run dev        # 开发：Tauri 内置 dev server 直接读项目根 ui/，改 HTML 热重载
npm run build      # 产出单文件 exe / NSIS / MSI 安装包
```

纯逻辑测试（**不需要 Windows**，macOS/Linux 上也能跑）：

```bash
# 共享规格的 40 项回归用例（Node 参考实现）
node spec/verify.mjs

# Rust 侧复用同一份用例（在 Windows 上执行）
cd windows/src-tauri && cargo test
```

界面原型在项目根共享的 `ui/index.html`（键帽数据由 `ui/bindings.js` 提供）。可以脱离 Tauri 直接用浏览器打开，会显示「预览模式」并渲染键帽效果图、开关和状态灯。

## 首次构建检查清单

以下都是**静态推断、未验证**，首次 `cargo build` 报错时优先看这些：

1. **Tauri v2 API**：`TrayIconBuilder::with_id("main")`、`WebviewWindowBuilder::new(app, ...)`、`Image::from_bytes`、`app.exit(0)` 在不同 2.x 小版本里签名可能变化，按编译器提示加 `.build(app)?` / `app.handle()` 等。
2. **`withGlobalTauri`**：`tauri.conf.json` 里开启后，前端才能用 `window.__TAURI__.core.invoke`；若该配置项改名，改用 `@tauri-apps/api/core` 的打包导入。
3. **`windows-sys` FFI**：`SetWindowsHookExW` 的 `HHOOK` 若被定义为整数而非指针，`hook.is_null()` 要改成 `hook == 0`；`GetMessageW` 的 `HWND` 参数同理。
4. **`frontendDist`**：共享 UI 在项目根 `ui/`，配置里写的是 `../../ui`（相对 `tauri.conf.json` 所在目录）。dev 与 build 都走同一份配置，由 Tauri 内置 dev server 提供热重载，不依赖外部 `serve`。
5. **图标**：`icon.ico` 是 PNG-in-ICO（Vista+ 支持）；若 Tauri 打包报图标格式错误，用 `tauri icon assets/icons/AppIcon-1024.png` 重新生成全套。

## 与原脚本的键位覆盖

**没有全复刻。** 完整对照见 `spec/keybindings.json` 的 `scriptCoverage`（16 条规则逐条标注 `status` 与原因）：

- **已复刻**：`!i/k/j/l/u/o`（方向与行首行尾）、`!n/!m`（水平滚轮）、`!h/!y`（垂直滚轮，但缺 VS Code 分支）、`$!d`（删整行，但白名单运行时未接通）。
- **规格已写、运行时未接通**：`RAlt::Shift`、`>^b/>^g`（右 Ctrl 打开网页）——`hook.rs` 还缺左右修饰键区分与前台进程名。
- **有意改了触发键**：原脚本 `^!`（Ctrl+Alt）做选中，骨架改用 **Alt+Shift** 保留选区。
- **完全未复刻**：`CapsLock→Esc`（建议走系统修饰键设置）、F8 窗口置顶、F10、Alt+Tab 鼠标移动、Win 组合 4 条、`>^f` 复制翻译、热字符串 `:::tabc::`、中键手势、光标处输入法提示。

## 已知待补齐（按优先级）

| 项 | 说明 |
| --- | --- |
| 左右修饰键区分 | 用 `GetAsyncKeyState(VK_RMENU/VK_RCONTROL)` 支撑「右 Alt→Shift」「右 Ctrl+B/G」 |
| 前台进程白名单 | `GetForegroundWindow` + `QueryFullProcessImageNameW`，把进程名传给 `remap` 的 `front_app`，启用 VS Code 放行 |
| 托盘浮窗定位 | 当前点击只 `show()`；需按托盘图标位置、任务栏方向、DPI、多显示器计算窗口坐标 |
| Alt 状态恢复 | `tap()` 临时松开 Alt 后没有恢复；长按重复、物理 Alt 松开时的状态是否打架，需真机实测 |
| 开机自启 | `set_autostart` 是空实现；写 HKCU Run 项或接 Tauri autostart 插件 |
| 高完整性级别窗口 | 低级钩子在管理员权限窗口前可能失效，必要时让进程以相同 IL 运行 |
| 代码签名 | 对外分发需要 Authenticode 证书，否则 SmartScreen 会拦 |

## 与 macOS 版的关系

- 两端共用 `spec/keybindings.json`：映射表、动作语义、应用白名单、40 项回归用例。
- `spec/verify.mjs` 是**可执行参考实现**，Node 上验证规格自洽；Rust 与 Swift 实现都应与之对齐。
- 界面 `ui/index.html` 复刻了 macOS 版的键帽网格与配色（蓝＝方向、橙＝动作、绿＝滚轮、紫＝修饰键）。
- macOS 版是已完成并实测的参考；Windows 版是重建骨架。**静态推断不等于运行时事实**，所有按键行为都必须在 Windows 真机上验证。

## 授权

`windows/` 与 `spec/` 属于根目录 [MIT License](../LICENSE) 覆盖范围。本目录**不包含**任何 AutoHotkey 脚本代码或 `KeyMap.exe` 二进制；实现是按行为规格重新编写的。历史文件的授权状态见 [`original/README.md`](../original/README.md)。
