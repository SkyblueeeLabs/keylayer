# original/ — 历史资料（不在 MIT 授权范围内）

这里存放多年前开发的 Windows 版 KeyMap 的遗留物，仅用于功能规格取证与对照。**这些文件不受根目录 `LICENSE`（MIT）覆盖，也不随开源仓库分发。**

| 文件 | 说明 | 授权状态 |
| --- | --- | --- |
| `KeyLayer_recovered.ahk` | 从 exe 资源段恢复的 AutoHotkey v1.1.33.09 脚本，257 行 | 版权归原作者；其中 `GetCaret`、`IME_GetConvMode`、`GetGUIThreadInfo_hwndActive` 等辅助函数可能源自 AHK 社区流传的公共片段，原创性与来源未逐一核实 |
| `KeyMap.exe` | 原始 PE32+ x86-64 编译产物（Ahk2Exe），内嵌 AutoHotkey 解释器 | AutoHotkey 本体为 **GPLv2**；编译产物是否整体受 GPL 约束存在争议（官方论坛与社区 Wiki 意见相左），因此不重新授权、不分发 |

因此：

- `KeyMap.exe` 已加入 `.gitignore`，请勿提交到公开仓库或打进 Release 包。
- 若希望把 AHK 脚本也纳入 MIT，请先确认其中不含第三方代码片段，再在根目录 `README.md` 的「许可范围」中补上声明。
- 脚本内容只是**行为规格来源**；macOS 实现（`src/`）是独立的全新 Swift 代码，与 AutoHotkey 运行时无关。
- 完整取证过程见 `docs/REVERSE_ENGINEERING.md`。
