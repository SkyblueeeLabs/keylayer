# KeyLayer

<p align="center">
  <img src="assets/icons/AppIcon-256.png" width="96" alt="KeyLayer">
</p>

<p align="center">打字和写代码时，让双手不用离开键盘。</p>

<p align="center">
  <a href="https://github.com/SkyblueeeLabs/keylayer/releases/latest"><img src="https://img.shields.io/github/v/release/SkyblueeeLabs/keylayer?label=download" alt="download"></a>
</p>

打错字时，直接用键盘调整，不必离开主键区去够鼠标选中再删。移动光标、跳到行首行尾、删除整行、滚动页面，都在同一套指法里完成；写代码时也一样。

<p align="center">
  <img src="docs/images/panel-windows-0.1.0.png" width="340" alt="KeyLayer Windows 托盘面板">
</p>

<p align="center">Windows 托盘面板 · macOS 菜单栏应用</p>

## 下载

两端都在 [Releases](https://github.com/SkyblueeeLabs/keylayer/releases/latest) 提供，当前版本 `0.1.0`。

**Windows**

- **免安装**：`KeyLayer_0.1.0_x64_portable.exe`，单个文件，复制到任意目录即可，不需要同目录 DLL。
- **安装版**：`KeyLayer_0.1.0_x64-setup.exe`（NSIS）或 `KeyLayer_0.1.0_x64_en-US.msi`。

**macOS**

- `KeyLayer_0.1.0_macos_arm64.zip`：Apple Silicon（arm64），macOS 13+。解压后把 `KeyLayer.app` 拖进「应用程序」。

文件校验和见同页的 `SHA256SUMS.txt`。

两端构建都没有代码签名。Windows 上 SmartScreen 可能提示，选择「更多信息 → 仍要运行」即可；macOS 版是本机自签名、未经 Apple 公证，首次打开需右键 → 打开，或执行 `xattr -dr com.apple.quarantine /Applications/KeyLayer.app`。也可以直接从源码构建。

## 使用

macOS 按住 **⌥** 或 **⌘**，Windows 按住 **Alt**；加 **Shift** 保留选区。

| 按键 | 效果 |
| --- | --- |
| `i` / `k` | 上 / 下 |
| `j` / `l` | 左 / 右 |
| `u` / `o` | 行首 / 行尾 |
| `d` | 删除整行（在 VS Code 内放行原键） |
| `h` / `y` | 向下 / 向上滚动 |
| `n` / `m` | 向左 / 向右滚动 |

右 **Option / Alt** 当作 `Shift`；右 **Ctrl / ⌃** + `B` / `G` 打开百度 / Google。

Ctrl 组合一律放行。macOS 的 `--cmd-only` 可以让所有映射只认 ⌘，把 ⌥ 留给特殊字符输入。

Windows 的托盘面板里可以随时停用映射、设置开机自启或退出。

## 安装

### Windows

- Windows 10/11 x64，需要 **WebView2 Runtime**：Win11 自带，Win10 一般随 Edge 已安装。
- 免安装版不需要额外 DLL；把 exe 挪到其他目录后，如果之前开过「开机自启」，需要在新位置重新勾选一次。
- 自行构建：`npm run build:win`，exe 和安装包在 `windows/src-tauri/target/release/`。

### macOS

下载 zip 解压后拖进「应用程序」，首次打开依次授权「设备控制与数据访问」和「输入监控」。被 Gatekeeper 拦住时右键 → 打开即可。

自行构建：

```bash
bash scripts/build.sh
./KeyLayer --self-test
open "$PWD/KeyLayer.app"
```

重建后如果权限失效，运行：

```bash
bash scripts/fix-permissions.sh
```

## 构建与测试

```bash
npm run check                  # 共享用例 + 生成文件一致性
npm test                       # 40 项回归用例
npm run build:win              # Windows：exe + NSIS/MSI
npm run build:mac              # macOS：CLI + App + 签名 + 自测
cd windows/src-tauri && cargo test
```

Windows 侧的构建细节、真机验证记录和调试开关见 [`windows/README.md`](windows/README.md)。

## 背景

最早是 Windows 上的 AutoHotkey 脚本 `KeyMap.exe`。源码丢失后，从 exe 资源里找回了脚本，先做了 macOS 版；Windows 版则按同一份行为规格用 Tauri v2 重写，不再内嵌 AutoHotkey。取证过程见 [`docs/REVERSE_ENGINEERING.md`](docs/REVERSE_ENGINEERING.md)。

## 实现

- **一份规格**：[`spec/keybindings.json`](spec/keybindings.json) 是唯一真相源，`npm run spec` 生成两端的键位表；40 项用例在 Node、Rust、Swift 三处对齐。
- **macOS**：Swift + `CGEventTap`，界面用 SwiftUI 菜单栏。
- **Windows**：Rust + Tauri v2 + `WH_KEYBOARD_LL`，界面是共享的 `ui/index.html`，用 WebView2 渲染。

两端的平台差异（权限模型、事件拦截、托盘）各自实现，行为规格保持同步。

## 已知限制

- macOS：滚轮方向受「自然滚动」设置影响；右 `⌥` → `⇧` 在个别应用中仍需实测；`⌥D` 是破坏性操作，误触会删除整行。
- Windows：点面板外自动收起依赖真实前台焦点；以管理员权限运行的窗口可能拦截钩子；对外分发需要代码签名。
- 原脚本的输入法状态浮窗、中键手势、Win 键组合等未移植，详见 [`docs/REVERSE_ENGINEERING.md`](docs/REVERSE_ENGINEERING.md)。

## 隐私

程序不联网、不上传数据；运行日志只记录键码和动作类型，不记录输入的字符内容。`--debug` 会逐条输出键码，调试日志请勿外发。

## 许可

[MIT License](LICENSE)。`original/` 下的历史文件不在 MIT 范围内，说明见 [`original/README.md`](original/README.md)。
