import Cocoa

// KeyLayerCLI.swift — 命令行入口（调试 / 自测用）
// 编译：swiftc -O KeyLayerCore.swift KeyLayerCLI.swift -o KeyLayer
// 与菜单栏 App 二选一运行，不要同时开，否则事件会被处理两次。

func selfTest() -> Int32 {
    let cmd = CGEventFlags.maskCommand
    let opt = CGEventFlags.maskAlternate
    let shift = CGEventFlags.maskShift
    let ctrl = CGEventFlags.maskControl
    var failures = 0

    func R(_ k: Int, _ c: String, _ s: String) -> String {
        "replace:\(k):cmd=\(c):shift=\(s):alt=false"
    }

    func expect(_ name: String, _ code: Int64, _ flags: CGEventFlags, _ want: String,
                state: ModifierState = ModifierState(), cmdOnly: Bool = false,
                frontID: String? = nil) {
        let got = describe(remap(keyCode: code, flags: flags, state: state,
                                 cmdOnly: cmdOnly, frontBundleID: frontID))
        let ok = got == want
        print("\(ok ? "PASS" : "FAIL")  \(name)")
        if !ok { print("      got=\(got) want=\(want)"); failures += 1 }
    }

    expect("⌘i → ↑", 34, cmd, R(126, "false", "false"))
    expect("⌘j → ←", 38, cmd, R(123, "false", "false"))
    expect("⌘k → ↓", 40, cmd, R(125, "false", "false"))
    expect("⌘l → →", 37, cmd, R(124, "false", "false"))
    expect("⌥i → ↑", 34, opt, R(126, "false", "false"))
    expect("⌥j → ←", 38, opt, R(123, "false", "false"))
    expect("⌥k → ↓", 40, opt, R(125, "false", "false"))
    expect("⌥l → →", 37, opt, R(124, "false", "false"))
    expect("⌘⇧j → ⇧←", 38, cmd.union(shift), R(123, "false", "true"))
    expect("⌥⇧j → ⇧←", 38, opt.union(shift), R(123, "false", "true"))
    expect("flagsChanged 状态兜底 ⌥", 34, [], R(126, "false", "false"),
           state: ModifierState(command: false, option: true, rightControl: false))
    expect("单独 i 不改写", 34, [], "pass")
    expect("⌃⌘i 不改写", 34, cmd.union(ctrl), "pass")
    expect("⌃⌥i 不改写", 34, opt.union(ctrl), "pass")
    expect("⌘a 不改写", 0, cmd, "pass")
    expect("--cmd-only 下 ⌥i 放行", 34, opt, "pass", cmdOnly: true)
    expect("--cmd-only 下 ⌘i 生效", 34, cmd, R(126, "false", "false"), cmdOnly: true)

    expect("⌥u → ⌘← 行首", 32, opt, R(123, "true", "false"))
    expect("⌥o → ⌘→ 行尾", 31, opt, R(124, "true", "false"))
    expect("⌘u → ⌘← 行首", 32, cmd, R(123, "true", "false"))
    expect("⌘o → ⌘→ 行尾", 31, cmd, R(124, "true", "false"))
    expect("⌥⇧u → ⌘⇧← 选中到行首", 32, opt.union(shift), R(123, "true", "true"))
    expect("⌥⇧o → ⌘⇧→ 选中到行尾", 31, opt.union(shift), R(124, "true", "true"))
    expect("⌃⌥u 不改写", 32, opt.union(ctrl), "pass")
    expect("单独 u 不改写", 32, [], "pass")
    expect("单独 o 不改写", 31, [], "pass")

    expect("⌥d 非 VS Code → 删除整行", 2, opt, "seq:5")
    expect("⌥d VS Code → 放行原键", 2, opt, "pass", frontID: "com.microsoft.VSCode")
    expect("⌘d VS Code → 放行原键", 2, cmd, "pass", frontID: "com.microsoft.VSCode")
    expect("⌥d VSCodeInsiders → 放行", 2, opt, "pass", frontID: "com.microsoft.VSCodeInsiders")
    expect("⌥h → 滚轮下", 4, opt, "scroll:0:-3")
    expect("⌥y → 滚轮上", 16, opt, "scroll:0:3")
    expect("⌥n → 水平滚轮左", 45, opt, "scroll:-3:0")
    expect("⌥m → 水平滚轮右", 46, opt, "scroll:3:0")
    expect("单独 h 不改写", 4, [], "pass")
    expect("右 Ctrl+b → 百度", 11, ctrl, "open:https://www.baidu.com",
           state: ModifierState(command: false, option: false, rightControl: true))
    expect("右 Ctrl+g → Google", 5, ctrl, "open:https://www.google.com",
           state: ModifierState(command: false, option: false, rightControl: true))
    expect("左 Ctrl+b 不触发", 11, ctrl, "pass")
    expect("右 Ctrl+a 不触发", 0, ctrl, "pass",
           state: ModifierState(command: false, option: false, rightControl: true))

    let roptDown = rightOptionToShift(keyCode: 61, flags: opt)
    let roptUp = rightOptionToShift(keyCode: 61, flags: [])
    let roptOther = rightOptionToShift(keyCode: 58, flags: opt)
    let okDown = roptDown?.keyCode == 56 && roptDown!.flags.contains(.maskShift) && !roptDown!.flags.contains(.maskAlternate)
    let okUp = roptUp?.keyCode == 56 && !roptUp!.flags.contains(.maskShift) && !roptUp!.flags.contains(.maskAlternate)
    let okOther = roptOther == nil
    print("\(okDown ? "PASS" : "FAIL")  右 Option 按下 → Shift")
    print("\(okUp ? "PASS" : "FAIL")  右 Option 松开 → 释放 Shift")
    print("\(okOther ? "PASS" : "FAIL")  左 Option 不受影响")
    if !(okDown && okUp && okOther) { failures += 1 }

    let total = 40
    print(failures == 0 ? "\n\(total)/\(total) 通过" : "\n\(failures) 组失败")
    return failures == 0 ? 0 : 1
}

@main
struct KeyLayerCLI {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.contains("--self-test") { exit(selfTest()) }

        let controller = EventTap()
        guard controller.install(debug: args.contains("--debug"),
                                 useSession: args.contains("--session"),
                                 cmdOnly: args.contains("--cmd-only")) else {
            fputs("创建事件 tap 失败。请检查「辅助功能」与「输入监控」授权并重启终端后重试。\n", stderr)
            exit(1)
        }
        log("KeyLayer CLI")
        log("  ⌘/⌥ + i/j/k/l 方向键 · u/o 行首行尾 · d 删整行 · h/y/n/m 滚轮 · 右⌥→⇧ · 右⌃+b/g 网址")
        log("  --cmd-only / --debug / --session / Ctrl+C 退出")
        CFRunLoopRun()
    }
}
