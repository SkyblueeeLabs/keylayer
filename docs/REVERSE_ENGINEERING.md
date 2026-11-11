# 逆向取证记录：KeyMap.exe → AHK 脚本

本文记录本项目如何从原始 Windows 二进制中恢复功能规格，以及哪些结论是证据、哪些只是推测。目标软件为**自有软件**，用途为**源码丢失后的功能恢复与学习研究**，产出仅用于本项目重建，不用于分发破解或侵权产品。

## 功能解释

`original/KeyMap.exe` 并非需要反编译的原生逻辑，而是 **AutoHotkey v1.1.33.09 编译产物**：AHK 脚本源码以 UTF-8 明文嵌在 PE 的 `.rsrc` 资源段里，直接从文件字节即可读出。因此本项目**没有使用 Ghidra / IDA 等反编译引擎**，也没有运行原程序。

恢复出的脚本共 257 行，是一个全局改键工具，核心规则（第 39–61 行，AHK 语法 `!`=Alt、`^`=Ctrl、`+`=Shift、`#`=Win）：

| 脚本行 | 规则 | 含义 |
| --- | --- | --- |
| 39, 41, 43, 45 | `!i/k/j/l → {Up}/{Down}/{Left}/{Right}` | Alt + 四键 = 方向 |
| 47, 49 | `!u → {Home}`、`!o → {End}` | 行首 / 行尾 |
| 51–61 | `^!` + 六键 `→ +{...}` | Ctrl+Alt 组合加 Shift 用于选中 |
| 33 | `RAlt::Shift` | 右 Alt 改 Shift |
| 35 | `$CapsLock::sendInput {Esc}` | Caps Lock 改 Esc |
| 63–85 | `$!d / $!h / $!y / !n / !m` | 含 `WinActive("ahk_exe Code.exe")` 的应用条件分支、滚轮、整行删除 |
| 87–93 | `#o / #j / #m / #n` | Win 键组合（虚拟桌面） |
| 95–110, 157 | `>^b / >^g / >^f` | 右 Ctrl 打开网页、复制并调用外部 `python KeyMap-translator.py` |
| 112–119 | `:::tabc::` | 热字符串 |
| 120–167 | 中键手势 `gtrack` | 1 ms 采样鼠标方向的状态机 |
| 168–255 | `WatchCaret` | 用 `imm32\ImmGetDefaultIMEWnd`、`oleacc\AccessibleObjectFromWindow` 在光标处显示中/英状态 |

脚本另有 `SetTimer, Re, 7200000`（每 2 小时 Reload，AHK 防卡死）、`FileCreateDir %A_MyDocuments%\KeyMap`、`SetWorkingDir` 等启动逻辑，以及一个半透明 GUI 小窗（华文楷体，显示「中」「A」「中A」）。

**结论**：用户描述的「Alt + i/j/k/l = 上下左右、u/o = 每行最左侧/最右侧」与脚本完全一致；`Home/End` 在 Windows 文本控件里正是行首/行尾。

## 证据清单

| 项 | 值 |
| --- | --- |
| 目标文件 | `original/KeyMap.exe` |
| 文件类型 | `PE32+ executable (GUI) x86-64, for MS Windows` |
| 大小 | 1,223,680 bytes |
| SHA-256 | `7eddd51f15221fef57bb1674f81714db4695785db6ea46a601dadb74db8d4cf5` |
| PE 节区 | 7 节；`.rsrc` VA `0x12E000`、Raw `0x124000`、大小 `0x6C00` |
| 导入表 RVA | `0x10BF04`，大小 `0x12C` |
| 脚本起点 / 终点（文件偏移） | `0x129168` / `0x12A466` |
| 脚本字节数 | 4,862 bytes，UTF-8 |
| 脚本 SHA-256 | `40b5ec18e7bbe76ccc5e20bc6df9795a4c4eb648297d0af44f44adc02b980330` |
| 脚本首行 | `; <COMPILER: v1.1.33.09>` |
| 恢复产物 | `original/KeyLayer_recovered.ahk`（257 行） |
| 关键规则位置 | 39–49（方向与行首行尾）、51–61（选中组合） |

**导入表佐证**（说明这确实是键盘钩子 / 改键工具，而非巧合的字符串）：

- `USER32.dll`：`SetWindowsHookExW`、`UnhookWindowsHookEx`、`CallNextHookEx`、`SendInput`、`keybd_event`、`RegisterHotKey`、`GetAsyncKeyState`、`GetKeyboardState`、`SetKeyboardState`、`MapVirtualKeyExW`、`VkKeyScanExW`、`ToUnicodeEx`、`GetKeyboardLayout`
- `KERNEL32.dll`：`GetPrivateProfileStringW`、`WritePrivateProfileStringW`、`GetPrivateProfileSectionW`（INI 配置读写）
- `WINMM.dll`、`PSAPI.DLL`、`WININET.dll`、`ole32.dll`、`OLEAUT32.dll` 等

**不可采信的尝试（方法论教训）**：早期按虚拟键码字节对（如 `4C 27`＝`l`→`VK_RIGHT`、`55 24`＝`u`→`VK_HOME`）在 `.text` 段搜索，得到若干命中，但这些全是 x64 机器码中 REX 前缀（`0x4C`/`0x55`）加操作码（`0x27`/`0x24`）的巧合。**该结果已弃用，本文所有结论不依赖它**；最终证据来自资源段明文。

## 局限与未知

- 脚本第 2–3 行把工作目录设为 `%A_MyDocuments%\KeyMap`，运行时可能读取**外部 INI / 脚本文件**覆盖或扩展规则；本机没有该目录，这部分属于**未知**。
- 资源段里的明文是**编译期嵌入的脚本**，不等于运行时实际生效的完整配置。
- 未运行原程序、未做动态捕获、未反编译；所有实现路径结论均为**静态推断**，不是运行时事实。
- 资源段后半段 100+ 行热键（中键手势、IME 提示、窗口置顶等）未逐一验证行为。
- 恢复的是**脚本逻辑与行为规格**，不是「原始源码还原」；编译期注入的尾部标记（`sjxp_This_and_next_line_added_by_Ahk2Exe`）也一并保留在文件里。
- REA 工具链未安装、未使用；本次取证用的是只读的 PE 结构解析与字符串提取。

## 重建建议

已在 `src/KeyLayerCore.swift` 中重建的部分，以及 Windows → macOS 的语义映射：

| Windows 机制 | macOS 对应 | 备注 |
| --- | --- | --- |
| `SetWindowsHookEx(WH_KEYBOARD_LL)` | `CGEventTap`（`kCGHIDEventTap` + `headInsertEventTap`） | 需辅助功能 + 输入监控 TCC 授权 |
| `VK_HOME` / `VK_END` | `⌘←` / `⌘→` | 不是 Mac 的 Home/End 键码（那是文档首尾） |
| `{Home}+{End}+{Right}{BS}{Home}` | `⌘← + ⌘⇧→ + ⇧→ + Delete + ⌘←` | 依赖 Cocoa 选区语义，需实测 |
| `SendInput` / `keybd_event` | `CGEvent(keyboardEventSource:virtualKey:keyDown:)` + `post(tap:)` | 合成事件避免被自身 tap 二次改写 |
| `Click, WheelDown/Up` | `CGEvent(scrollWheelEvent2Source:…)` | 方向受「自然滚动」影响 |
| `WinActive("ahk_exe Code.exe")` | `NSWorkspace.shared.frontmostApplication?.bundleIdentifier` | 白名单写在 `vscodeBundleIDs` |
| `#` Win 键组合 | 无对应键 | 未移植 |
| Caps Lock → Esc | 系统设置「修饰键」里直接改 | 见 README「Caps Lock 相关」 |

验证方式：`./KeyLayer --self-test`（40 项纯逻辑用例）覆盖映射表与动作分发；真实按键效果用 `./KeyLayer --debug` 观察 `flags` 与 `Action`，或看 `KeyLayer.runtime.log`。

**未移植**的部分及原因见 README「已知限制与未实现」：`KeyMap-translator.py` 缺失、Windows IME/oleacc 专属的光标提示、中键手势、Win 键组合、F8/F10、热字符串、定时 Reload。
