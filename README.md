# KeyLayer for macOS

一个常驻菜单栏的小工具，把 Windows 上 `Alt + i/j/k/l/u/o` 的改键习惯带到 macOS：按住修饰键，用字母键完成光标移动、行首行尾跳转、整行删除和滚轮操作。

> 原名 `KeyMap`，2026 年 11 月更名为 **KeyLayer（键层）**。

项目起点是一次**自有软件的功能恢复**：原来在 Windows 上用的是一个 AutoHotkey 编译的 `KeyMap.exe`，脚本源码一度丢失。后来从 exe 的资源段里找回了明文 AHK 脚本，据此在 macOS 上用 Swift + `CGEventTap` 重建了核心行为。完整取证记录见 [`docs/REVERSE_ENGINEERING.md`](docs/REVERSE_ENGINEERING.md)。

Windows 侧另起一条线：按同一份行为规格用 **Tauri v2 重写**（不内嵌 AutoHotkey），并带上同款托盘弹窗界面，见 [`windows/README.md`](windows/README.md)。两端共用 [`spec/keybindings.json`](spec/keybindings.json) 与 40 项回归用例。

## 许可证

采用 [MIT License](LICENSE)：任何人都可以免费使用、复制、修改、合并、发布、分发、再授权乃至出售本软件，唯一条件是保留版权声明与许可文本。

覆盖范围：`src/`、`scripts/`、`assets/`、`docs/`、`README.md`、`.gitignore`（macOS 实现、图标、构建脚本与文档）。**`original/` 里的历史文件不在 MIT 范围内**，原因见 [许可范围](#许可范围) 与 `original/README.md`。

> 维护者待办：确认版权持有人与年份（`Copyright (c) 2026 Skyblueee`）无误；补 `CONTRIBUTING.md`。

---

## 目录

- [功能](#功能)
- [界面](#界面)
- [环境要求](#环境要求)
- [快速开始](#快速开始)
- [权限与签名](#权限与签名)
- [目录结构](#目录结构)
- [架构](#架构)
- [双端开发架构](#双端开发架构)
- [构建脚本](#构建脚本)
- [Windows 版](#windows-版)
- [测试与调试](#测试与调试)
- [已知限制与未实现](#已知限制与未实现)
- [路线图](#路线图)
- [许可范围](#许可范围)
- [贡献](#贡献)
- [隐私与安全](#隐私与安全)

---

## 功能

触发修饰键默认是 **⌥（Option）或 ⌘（Command）**，两者都认（Windows 的 Alt 在 Mac 键盘上对应 Option，保留肌肉记忆）。加 **⇧** 会保留 Shift 用于选中文本。

| 按键 | 输出 | 说明 |
| --- | --- | --- |
| `i` | `↑` | 上 |
| `j` | `←` | 左 |
| `k` | `↓` | 下 |
| `l` | `→` | 右 |
| `u` | `⌘←` | 行首（Windows `{Home}` 的 Mac 等价） |
| `o` | `⌘→` | 行尾（Windows `{End}` 的 Mac 等价） |
| `d` | 删除整行 | 合成 `⌘← + ⌘⇧→ + ⇧→ + Delete + ⌘←`；VS Code 内放行原键 |
| `h` / `y` | 垂直滚轮下 / 上 | 合成 `CGEvent` 滚轮事件 |
| `n` / `m` | 水平滚轮左 / 右 | 同上 |
| 右 `⌥` | `⇧` | 按 `keyCode 61` 识别，改写成 Shift |
| 右 `⌃` + `b` / `g` | 打开百度 / Google | 按 `keyCode 62` 识别右 Control |

- **Ctrl / Control 组合一律放行**，避免误伤系统快捷键。
- `--cmd-only` 可让所有映射只认 ⌘，把 ⌥ 还给 macOS 的特殊字符输入（⌥+字母 现在被占用 11 个）。
- 触发键与目标键的虚拟键码表见 `src/KeyLayerCore.swift` 的 `remap()`。

### Caps Lock 相关

原 Windows 脚本把 Caps Lock 映射成 Esc（`$CapsLock::sendInput {Esc}`），因为输入法切换用的是 Ctrl+空格。在 macOS 上**不需要写进本程序**：

1. 系统设置 → 键盘 → 文字输入 → 编辑 → 关闭「使用大写锁定键切换输入法」；
2. 系统设置 → 键盘 → 键盘快捷键 → 修饰键 → Caps Lock 设为 **Escape**；
3. 输入法切换用 macOS 默认的 `Ctrl+空格`。

这是系统驱动层重映射，比在 `CGEventTap` 里拦 `flagsChanged` 更干净可靠。

---

## 界面

`KeyLayer.app` 是 `LSUIElement` 菜单栏应用，不占 Dock。右上角状态项显示单色键盘图标 + `KL` 文字，点开是一个 popover：

- **生效开关**：真正调用 `CGEvent.tapEnable` 启停事件 tap，状态存 `UserDefaults`，重启保留；停用后状态项文字变 `KM 关`。
- **状态灯**：绿＝事件 tap 已建立，橙＝未建立。判据是 `CGEvent.tapCreate` 的实际结果，不是 `AXIsProcessTrusted()`。
- **映射效果图**：迷你键帽网格，蓝＝方向键位、橙＝动作键、绿＝滚轮、紫＝右 ⌥。
- **权限设置**按钮、**开机自启**（`SMAppService`）、**退出**。

图标源文件与生成脚本在 `assets/icons/` 和 `scripts/gen-icons.swift`。采用**双尺寸策略**：128px 及以上带 `KeyLayer` 字标，更小的尺寸自动切到无字标的紧凑版，避免文字糊掉；菜单栏用单色模板图，Windows 托盘用简化的六键标记。App 图标本身是透明底 + 玻璃渐变 + 悬浮投影，`icon.ico` 与 `tray.png` 由同一脚本一并生成。

---

## 环境要求

- macOS 13+（使用 `MenuBarExtra` 无关的 AppKit `NSStatusItem` + `NSPopover`、`SMAppService`；实测 macOS 27.2）
- Xcode Command Line Tools（`swiftc`、`sips`、`iconutil`、`codesign`、`security`）
- Apple Silicon 或 Intel Mac 均可（当前产物为 arm64，源码无架构依赖）
- **辅助功能类权限**（见下节），否则 `CGEvent.tapCreate` 会直接失败

---

## 快速开始

```bash
git clone <your-repo-url>
cd KeyLayer

# 一条命令从源码构建 CLI + App（含图标生成与签名）
bash scripts/build.sh

# 先跑纯逻辑自测（不需要任何权限）
./KeyLayer --self-test

# 启动（建议从访达双击，不要从 CI/受限终端代启动）
open "$PWD/KeyLayer.app"
```

首次运行需要授权：

1. 系统设置 → 隐私与安全性 → **设备控制与数据访问**（macOS 27 里「辅助功能」的新名称）→ 勾选 `KeyLayer`；
2. 系统设置 → 隐私与安全性 → **输入监控** → 勾选 `KeyLayer`；
3. 弹窗选 **「退出并重新打开」**。

App 启动后若未授权会自动弹出系统授权对话框；界面里也有「请求系统授权」按钮。授权成功后 2 秒内自动补建事件 tap，无需重启。

> **命令行版与 App 版不要同时运行**，否则会有两个事件 tap。

---

## 权限与签名

这是本项目最容易踩坑的地方，务必读完。

**TCC 按代码签名身份授权，不是按路径。** `codesign -s -`（ad-hoc）签名的 designated requirement 是二进制的 `cdhash`，每次重新构建都会变；系统设置里开关看起来还是开的，但 `AXIsProcessTrusted()` 和 `CGEvent.tapCreate` 会静默失败。表现是「明明授权了却不生效」。

因此项目使用一张**本地自签名证书** `KeyLayer Local Dev`来稳定身份：

```
designated => identifier "com.skyblueee.keylayer" and certificate leaf = H"…"
```

只要用同一张证书签名，重建、改代码、换图标都不会丢授权。`build.sh` 会自动优先使用它；首次创建证书用：

```bash
bash scripts/fix-permissions.sh
```

该脚本会：退出旧实例 → `tccutil reset` 清掉失效的授权记录 → 若证书不存在则用 OpenSSL 生成并导入登录钥匙串 → 用证书重签 App → 从当前终端启动。若弹出钥匙串授权，点「始终允许」。

几个已验证的经验：

- **从其他脚本/受限终端 `open` 启动的 App，其 TCC 责任链可能与手动启动不同**，导致授权落不到该进程上。请从访达双击启动，或用自己的终端执行 `open`。
- 权限变更后 TCC 结果按进程缓存，需要「退出并重新打开」。
- 反复重建会留下多条同名授权记录，勾选的可能不是当前那一份；`tccutil reset` 或系统设置里用「−」删干净后重新勾选。
- `fix-permissions.sh` 是**一次性修复**，不是启动脚本。日常重启电脑、重启 App 都不需要再跑。

---

## 目录结构

```
KeyLayer/
├── README.md                    项目说明
├── LICENSE                      MIT 许可证
├── package.json                 双端统一命令入口
├── .gitignore                   忽略构建产物与本机数据
├── .github/workflows/ci.yml     双平台 CI（共享检查 + 各自编译/测试）
├── docs/
│   └── REVERSE_ENGINEERING.md  从 KeyMap.exe 恢复 AHK 脚本的取证记录
├── spec/
│   ├── keybindings.json         双平台共享行为规格与 40 项用例
│   └── verify.mjs               规格的 Node 参考实现与用例验证
├── src/
│   ├── Generated.swift          自动生成：键位表 / 目标键码 / 网址 / 白名单 / 键帽布局
│   ├── GeneratedTokens.swift    自动生成：配色 / 尺寸 / 字号（SwiftUI）
│   ├── KeyLayerCore.swift         共享核心：映射逻辑 + CGEventTap（无入口）
│   ├── KeyLayerCLI.swift          CLI 入口 + 40 项自测
│   ├── KeyLayerApp.swift          菜单栏 App + SwiftUI 界面
│   └── Info.plist               bundle 配置（LSUIElement、CFBundleIconFile）
├── scripts/
│   ├── gen-sources.mjs          从规格 + 设计令牌生成五份平台代码
│   ├── check.mjs                共享用例 + 生成一致性 + 三端引用检查
│   ├── build.sh                 一键构建（生成 → CLI + App + 图标 + 签名 + 自测）
│   ├── fix-permissions.sh       一次性修复权限与稳定签名
│   └── gen-icons.swift          Core Graphics 生成图标 PNG
├── assets/icons/                图标源资产（PNG 与 iconset）
├── ui/                          共享界面：index.html、tokens.json + 生成的 bindings.js / tokens.css
├── windows/                     Windows 版 Tauri v2 骨架（见 windows/README.md）
│   ├── src-tauri/               Rust 后端、配置与图标（含 generated.rs）
│   └── package.json
├── original/
│   ├── README.md                历史文件授权说明
│   ├── KeyMap.exe               原始 Windows 二进制（已忽略，不分发）
│   └── KeyLayer_recovered.ahk     从 exe 资源段恢复的 AHK 脚本
└── （以下为构建/运行产物，已被 .gitignore 忽略）
    ├── KeyLayer.app/              菜单栏 App bundle
    ├── KeyLayer.app.zip           发布用打包
    ├── KeyLayer                CLI 可执行文件
    └── KeyLayer.runtime.log       运行诊断日志
```

`.workbuddy/` 是本机工作区数据，不属于项目内容，已忽略，**请勿删除**。

---

## 架构

macOS 侧由 `spec/keybindings.json` 生成的 `src/Generated.swift` 提供全部键位数据；三个手写 Swift 文件负责逻辑与界面，两个 `@main` 分别编译到不同目标，避免入口冲突：

```
src/KeyLayerCore.swift  ──┬──> src/KeyLayerCLI.swift  ──> KeyLayer (CLI)
                        └──> src/KeyLayerApp.swift  ──> KeyLayer.app/…/KeyLayer
```

### `KeyLayerCore.swift`

- `remap(keyCode:flags:state:cmdOnly:frontBundleID:) -> Action`：纯函数，输入虚拟键码、修饰键状态、前台 app bundle id，输出一个 `Action`。
- `Action` 有五种：`pass`（放行）、`replace`（改写当前事件的 keyCode/flags）、`keySequence`（吞掉原事件并合成多键）、`scroll`（滚轮）、`open`（打开网址）。
- `EventTap`：创建 `kCGHIDEventTap` + `headInsertEventTap` 的 `CGEventTap`，把 `CFRunLoopSource` 挂到主线程 run loop。`install()` **不调用 `CFRunLoopRun()`**，由 CLI 或 App 各自的运行循环驱动。
- `flagsChanged` 里维护 `ModifierState`（command / option / rightControl），用于区分左右 Control、给改写兜底。
- 动作型事件**只在 `keyDown` 执行、`keyUp` 只吞掉**，避免删除整行跑两次。
- 合成事件的 keyCode 都不在 `remap` 表内，天然避免被自身 tap 二次改写。

### `KeyLayerCLI.swift`（CLI）

用于调试和回归测试：`--self-test`、`--debug`、`--cmd-only`、`--session`，之后进入 `CFRunLoopRun()`。

### `KeyLayerApp.swift`（App）

- `AppDelegate` 用 `NSStatusItem` + `NSPopover` + `NSHostingController` 承载 SwiftUI 视图（没用 `MenuBarExtra`，避免 accessory app 下状态项不显示的问题）。
- `TapManager` 持有 `EventTap`，2 秒轮询：刷新权限展示、并在 `tapOK == false` 时**无条件重试 `install()`**（不依赖可能误报的 `AXIsProcessTrusted()`）。
- `panelSize()` 用 `fittingSize` 测量 SwiftUI 内容高度，保证 popover 不留白、定位稳定。
- `uiLog()` 写 `KeyLayer.runtime.log`。

---

## 双端开发架构

**能共享**：行为规格、键位数据、回归用例、界面键帽数据。
**必须各写一份**：全局事件拦截（`CGEventTap` vs `SetWindowsHookExW`）、事件合成、托盘/菜单栏、权限模型、打包签名。所以不是「一套代码两边跑」，而是**共享层 + 平台适配层**。

| 层 | 内容 | 位置 |
| --- | --- | --- |
| 唯一真相源 | 映射表、动作语义、白名单、URL、40 项用例、覆盖清单 | `spec/keybindings.json` |
| 设计令牌 | 配色、尺寸、字号、分组色（平台无关） | `ui/tokens.json` → `ui/tokens.css`（CSS 变量）、`src/GeneratedTokens.swift`（SwiftUI 常量） |
| 代码生成 | 一次生成五份平台代码 | `scripts/gen-sources.mjs` → `src/Generated.swift`、`src/GeneratedTokens.swift`、`windows/src-tauri/src/generated.rs`、`ui/bindings.js`、`ui/tokens.css` |
| 参考实现 | 平台无关 `remap` + 40 用例 | `spec/verify.mjs` |
| 一致性门禁 | 用例、生成文件是否最新、三端是否真的引用了生成代码 | `scripts/check.mjs` |
| 平台适配（macOS） | `CGEventTap`、SwiftUI、`NSStatusItem`、`codesign` | `src/*.swift` |
| 平台适配（Windows） | 低级钩子、`TrayIcon`、WebView2、Authenticode | `windows/src-tauri/` |
| 各自打包 | `npm run build:mac` / `npm run build:win` | 只在对应平台执行 |

改键位或动作时**只改 `spec/keybindings.json`**，再跑 `npm run spec` 重新生成并校验；三端逻辑自动跟上。`npm run check` 会拦住「改了规格忘了生成」和「生成了但没引用」两种情况，CI 也会跑它。

UI 目前是两套渲染：macOS 用 SwiftUI、Windows 用共享的 `ui/index.html`（WebView2）。**数据层与视觉参数都已统一**：键帽数据走 `ui/bindings.js` / `Generated.swift`，配色、尺寸、字号走 `ui/tokens.json` 生成的 CSS 变量与 SwiftUI 常量；各端只保留渲染方式和平台控件（开关、浮窗）本身。这是菜单栏常驻小工具的常见取舍：WebView 的冷启动与常驻内存开销，对「点一下就要立刻弹出」的托盘面板不划算，SwiftUI 也更贴合系统深浅色与动效。

改配色或尺寸只改 `ui/tokens.json`，再 `npm run spec`；Web 与 SwiftUI 会同时更新，check 会确认两端都引用了生成文件。浅色/深色这类**运行时主题**仍由各宿主自行注入（Web 侧可覆盖同名 CSS 变量，SwiftUI 侧由系统语义色接管），不属于静态令牌。

**收敛成一份 Web UI 的条件**：当界面出现映射编辑表格、日志视图、设置分页等复杂交互，维护两份 UI 的成本超过 WebView 开销时再做。届时先定义平台无关的 bridge 契约（`get_status` / `set_enabled` / `get_bindings` / `quit`），Tauri 侧用 `invoke`、macOS 侧用 `WKScriptMessageHandler` 各实现一次，主题与尺寸由宿主注入 CSS 变量——**不是只共享一个 HTML 文件**。

## 构建脚本

| 脚本 | 作用 |
| --- | --- |
| `scripts/gen-sources.mjs` | 从规格与令牌生成 5 份平台代码（Swift ×2 / Rust / JS / CSS） |
| `scripts/check.mjs` | 共享用例 + 生成一致性 + 三端引用检查 |
| `scripts/build.sh` | 生成代码 → 图标 → 编译 CLI → 编译 App → 证书签名校验 → 跑自测 |
| `scripts/fix-permissions.sh` | 一次性：清 TCC 记录、创建/复用自签名证书、重签、从当前终端启动 |
| `scripts/gen-icons.swift` | 用 Core Graphics 画 `AppIcon-1024.png`、`MenuIcon.png`、`MenuIcon@2x.png` |

根目录 `package.json` 提供统一入口，**各平台只跑自己那条构建命令**：

```bash
npm run spec         # 从规格重新生成三端代码 + 一致性检查
npm run check        # 只检查（CI 用）
npm test             # 跑共享 40 项用例
npm run build:mac    # 仅 macOS
npm run build:win    # 仅 Windows
```

`build.sh` 支持环境变量覆盖输出，方便验证时不碰现有 App：

```bash
KEYLAYER_APP=/tmp/Test.app KEYLAYER_CLI=/tmp/km-cli bash scripts/build.sh
```

证书签名偶尔会因钥匙串交互挂起；`build.sh` 加了 15 秒超时，超时会回退 ad-hoc 并提示，不会把构建卡死。

发布打包：

```bash
zip -q -r KeyLayer.app.zip KeyLayer.app
```

---

## 测试与调试

```bash
npm run check                # 用例 + 生成一致性 + 三端引用检查（提交前跑）
node spec/verify.mjs         # 共享规格的 40 项用例（Node 参考实现，跨平台）
./KeyLayer --self-test      # macOS 侧 40 项纯逻辑测试，不需要权限
./KeyLayer --debug          # 逐条打印 keyDown/keyUp/flagsChanged 与 Action
cd windows/src-tauri && cargo test   # Windows 侧复用同一份用例（需 Rust）
```

自测覆盖：⌘/⌥ 四向映射、⌘⇧ 与 ⌥⇧ 保留选区、u/o 行首行尾、`--cmd-only`、Control 组合放行、`!d` 的 VS Code 白名单、滚轮四向、右 Ctrl 打开网址、右 Option→Shift。

诊断日志 `KeyLayer.runtime.log` 会记录启动、权限状态、tap 是否建立、popover 尺寸、开关切换等。排查「不生效」时按顺序看三件事：

1. `tapOK` 是否为 `true`（事件通道）；
2. `--debug` 里按键的 `flags` 是否带触发修饰键（`0x100000`＝Command，`0x80000`＝Option）；
3. `Action` 是否命中（`pass` 说明条件没满足）。

---

## 已知限制与未实现

**静态推断不等于运行时事实。** 以下项目里，逻辑已通过自测，但真实按键效果依赖具体应用与系统版本，仍需实测：

- 滚轮方向（`wheel1/wheel2` 正负）会受「自然滚动」设置影响；
- 右 `⌥` → `⇧` 改的是 `flagsChanged`，系统是否完全按 Shift 处理待验证；
- `keyCode 62` 是否对应你键盘的右 Control（外接键盘可能不同）；
- `⌥d` 的合成序列依赖 Cocoa 文本系统的选区行为，且是**破坏性操作**，误触会删除整行；
- `www.google.com` 在部分地区不可达。

**Windows 版目前只复刻了核心 11 个字母键**，且其中右 Alt、右 Ctrl、VS Code 白名单在运行时尚未接通。完整逐条对照见 `spec/keybindings.json` 的 `scriptCoverage`，构建侧说明见 `windows/README.md`。

**原脚本中未移植的部分**（见 `docs/REVERSE_ENGINEERING.md`）：

- `KeyMap-translator.py` 不在仓库里，复制并翻译选区、中键上划手势两处功能缺依赖；
- 光标处「中 / A」输入法状态浮动窗（依赖 Windows `imm32` / `oleacc`）；
- 中键手势状态机（Mac 触控板无中键，动作也是 Windows 特有）；
- Win 键组合 `#o/#j/#m/#n`、F8 窗口置顶、F10 大写锁定切换、热字符串 `::tabc::`；
- 每 2 小时自动 Reload（AHK 防卡死，Swift 版不需要）。

**其他**：`CFBundleIconFile` 在 macOS 27 上省略 `.icns` 后缀可正常解析；Finder 图标有缓存，替换图标后若没刷新，可 `touch KeyLayer.app`、`lsregister -f`、重启 Finder 或注销再登录。

---

## Windows 版

`windows/` 是按共享规格用 **Tauri v2 重写的 Windows 骨架**，不是给老 exe 套壳。这样既摆脱了 AutoHotkey GPLv2 解释器的捆绑争议，也能把 macOS 那套托盘弹窗界面搬过去。

| macOS 版 | Windows 等价 |
| --- | --- |
| `NSStatusItem` + `NSPopover` | `TrayIcon` + 无边框置顶窗口（失焦收起） |
| `CGEventTap` 改写事件 | `SetWindowsHookEx(WH_KEYBOARD_LL)` + `keybd_event` |
| `NSWorkspace` bundle id | 前台进程名（待实现） |
| `SMAppService` | HKCU Run 项（待实现） |

界面原型在项目根共享的 `ui/index.html`（键帽数据来自生成的 `ui/bindings.js`），可以直接用浏览器打开预览（会显示「预览模式」）；Rust 侧 `remap()` 与 `spec/verify.mjs` 复用同一份 40 项用例。构建步骤与「首次构建检查清单」见 [`windows/README.md`](windows/README.md)。

> 本机是 macOS，Windows 专属的钩子、托盘与窗口定位代码**没有编译或运行验证**，请在 Windows 机器上 `npm run build` 后按报错调整。已知待补齐：左右 Alt/Ctrl 区分、前台进程白名单、托盘浮窗按 DPI/多显示器定位、Alt 状态恢复、开机自启、管理员窗口的完整性级别问题。**静态推断不等于运行时事实。**

## 路线图

- [ ] 补 `CONTRIBUTING.md`（`LICENSE` 已采用 MIT）
- [ ] Windows 版：在 Windows 上完成首次 `cargo build`，按检查清单修正 FFI / Tauri API
- [ ] Windows 版：左右修饰键区分、前台进程白名单、托盘定位、开机自启
- [x] 按应用白名单做成可配置项（`spec.appWhitelist` → 生成表）
- [x] 映射表配置化（`spec/keybindings.json` + 三端代码生成）
- [x] UI 参数统一（`ui/tokens.json` → CSS 变量 / SwiftUI 常量）
- [ ] 界面复杂化后再评估 UI 收敛（先立 bridge 契约，再谈共享 Web UI）
- [ ] 停用态状态项加灰色斜杠（目前只改文字为 `KM 关`）
- [ ] 中键手势改用 Mac 上合适的触发方式重新设计
- [ ] CI 上跑 `--self-test` 与 `build.sh` 语法校验
- [ ] 通用安装包 / Homebrew cask

---

## 许可范围

| 内容 | 许可 |
| --- | --- |
| `src/`、`scripts/`、`assets/`、`docs/`、`spec/`、`windows/`、`README.md`、`.gitignore` | MIT（见 `LICENSE`） |
| `original/KeyLayer_recovered.ahk` | 历史资料，版权归原作者；第三方片段未核实，暂不授权 |
| `original/KeyMap.exe` | 内嵌 GPLv2 的 AutoHotkey 解释器，不授权、不分发，已加入 `.gitignore` |
| `KeyLayer.app/`、`KeyLayer.app.zip`、`KeyLayer` | 构建产物，随 MIT 源码自行构建；不单独发布二进制 |

选择 MIT 而不是 GPL/LGPL：MIT 对使用者几乎没有限制，允许商用和闭源衍生，符合「任何人都可以使用」。若连保留版权声明这一项也不需要，可改用 0BSD 或 CC0，但 MIT 在企业与开源社区里接受度最高。

两点提醒：许可证只能覆盖**你拥有著作权的内容**。若当年的 Windows 版属于职务作品、有共同作者，或引入了第三方代码，发布前请先确认权利归属；`original/README.md` 里也标注了 AHK 社区片段的待核实项。

## 贡献

欢迎 issue 与 PR。提交前请：

1. 跑 `bash scripts/build.sh` 与 `./KeyLayer --self-test`，确保 40 项全过；
2. 新增映射时**同步补 `selfTest()` 用例**，并说明证据来源（原 AHK 脚本行号，或用户实测行为）；
3. 涉及权限、签名、启动方式时，尽量在真实 macOS 上验证，静态推断请明确标注；
4. 不要提交 `KeyLayer.app/`、`*.zip`、`KeyLayer`、`KeyLayer.runtime.log`、`.DS_Store` 或 `.workbuddy/`。

代码风格：Swift 单文件、无第三方依赖；构建脚本只用系统自带工具（`swiftc` / `sips` / `iconutil` / `codesign` / `security` / `openssl`）。

---

## 隐私与安全

本工具需要「辅助功能 / 设备控制与数据访问」与「输入监控」权限，因为它必须全局拦截并改写键盘事件。请只授予你信任并自行构建的二进制。

- 程序**不联网、不上传任何数据**；`open` 动作只调用系统默认浏览器打开固定网址。
- 运行日志只记录事件元数据（keyCode、flags、动作类型、权限状态），**不记录输入的字符内容**。
- 但 `--debug` 会逐条输出按键的 keyCode，理论上可推断输入内容；调试日志请勿外发，尤其是在输入敏感信息时。
- `original/KeyMap.exe` 是原始 Windows 二进制，仅供本地取证与对照，已加入 `.gitignore`、不在 MIT 授权范围内；不要直接运行来源不明的二进制。
