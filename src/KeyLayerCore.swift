import Cocoa

// KeyLayerCore.swift — 共享核心：映射逻辑 + CGEventTap
// 证据：KeyLayer_recovered.ahk（AutoHotkey 脚本，从历史 KeyMap.exe 的资源段恢复）
// CLI 与菜单栏 App 共用本文件；本文件不含程序入口。

func log(_ s: String) {
    print(s)
    fflush(stdout)
}

func modifierLabels(_ flags: CGEventFlags) -> String {
    var parts: [String] = []
    if flags.contains(.maskCommand) { parts.append("command") }
    if flags.contains(.maskAlternate) { parts.append("option") }
    if flags.contains(.maskShift) { parts.append("shift") }
    if flags.contains(.maskControl) { parts.append("control") }
    return parts.isEmpty ? "-" : parts.joined(separator: "+")
}

struct ModifierState {
    var command = false
    var option = false
    var rightControl = false
}

struct KeyStroke {
    let keyCode: Int64
    let flags: CGEventFlags
}

enum Action {
    case pass
    case replace(keyCode: Int64, flags: CGEventFlags)
    case keySequence([KeyStroke])
    case scroll(dx: Int32, dy: Int32)
    case open(String)
}

func describe(_ a: Action) -> String {
    switch a {
    case .pass:
        return "pass"
    case .replace(let k, let f):
        return "replace:\(k):cmd=\(f.contains(.maskCommand)):shift=\(f.contains(.maskShift)):alt=\(f.contains(.maskAlternate))"
    case .keySequence(let s):
        return "seq:\(s.count)"
    case .scroll(let dx, let dy):
        return "scroll:\(dx):\(dy)"
    case .open(let u):
        return "open:\(u)"
    }
}

// 映射表、目标键码、网址与应用白名单统一来自 Generated.swift
// （由 spec/keybindings.json 生成，运行 `npm run spec` 重新生成）。

func deleteLineStrokes() -> [KeyStroke] {
    let cmd = CGEventFlags.maskCommand
    let shift = CGEventFlags.maskShift
    return [
        KeyStroke(keyCode: 123, flags: cmd),
        KeyStroke(keyCode: 124, flags: cmd.union(shift)),
        KeyStroke(keyCode: 124, flags: shift),
        KeyStroke(keyCode: 51, flags: []),
        KeyStroke(keyCode: 123, flags: cmd),
    ]
}

func remap(keyCode: Int64, flags: CGEventFlags, state: ModifierState,
           cmdOnly: Bool, frontBundleID: String?) -> Action {
    if state.rightControl && flags.contains(.maskControl) {
        if let u = Generated.urlActions.first(where: { $0.mac == keyCode }) {
            return .open(u.url)
        }
    }

    let hasCommand = flags.contains(.maskCommand) || state.command
    let hasOption = flags.contains(.maskAlternate) || state.option
    let triggered = cmdOnly ? hasCommand : (hasCommand || hasOption)
    guard triggered, !flags.contains(.maskControl) else { return .pass }

    guard let binding = Generated.macBinding(keyCode) else { return .pass }

    switch binding.action {
    case "delete-line":
        if let id = frontBundleID, Generated.vscodeBundleIDs.contains(id) { return .pass }
        return .keySequence(deleteLineStrokes())
    case "scroll-down":  return .scroll(dx: 0, dy: -3)
    case "scroll-up":    return .scroll(dx: 0, dy: 3)
    case "scroll-left":  return .scroll(dx: -3, dy: 0)
    case "scroll-right": return .scroll(dx: 3, dy: 0)
    default:
        guard let target = Generated.actionKeyCodes[binding.action] else { return .pass }
        var newFlags = flags
        newFlags.remove(.maskCommand)
        newFlags.remove(.maskAlternate)
        if target.needsCommand { newFlags.insert(.maskCommand) }
        return .replace(keyCode: target.mac, flags: newFlags)
    }
}

func rightOptionToShift(keyCode: Int64, flags: CGEventFlags) -> (keyCode: Int64, flags: CGEventFlags)? {
    guard keyCode == 61 else { return nil }
    var nf = flags
    nf.remove(.maskAlternate)
    if flags.contains(.maskAlternate) {
        nf.insert(.maskShift)
    } else {
        nf.remove(.maskShift)
    }
    return (56, nf)
}

func frontmostBundleID() -> String? {
    guard Thread.isMainThread else { return nil }
    return MainActor.assumeIsolated {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }
}

func openURL(_ s: String) {
    guard Thread.isMainThread else { return }
    MainActor.assumeIsolated {
        if let u = URL(string: s) { NSWorkspace.shared.open(u) }
    }
}

func postKeySequence(_ strokes: [KeyStroke]) {
    guard let src = CGEventSource(stateID: .hidSystemState) else { return }
    for s in strokes {
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: src,
                                  virtualKey: CGKeyCode(s.keyCode), keyDown: down) else { continue }
            e.flags = s.flags
            e.post(tap: .cghidEventTap)
        }
    }
}

func postScroll(dx: Int32, dy: Int32) {
    guard let src = CGEventSource(stateID: .hidSystemState),
          let e = CGEvent(scrollWheelEvent2Source: src, units: .line,
                          wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0) else { return }
    e.post(tap: .cghidEventTap)
}

final class EventTap {
    var tap: CFMachPort?
    var source: CFRunLoopSource?
    var state = ModifierState()
    var debug = false
    var useSession = false
    var cmdOnly = false
    var enabled = true
    var sawKey = false
    var sawRemap = false

    // 创建事件 tap 并把 source 挂到当前线程 run loop（CLI 与 App 都在主线程）
    // 返回 false 表示权限不足或创建失败
    func install(debug: Bool, useSession: Bool, cmdOnly: Bool) -> Bool {
        self.debug = debug
        self.useSession = useSession
        self.cmdOnly = cmdOnly

        let mask = CGEventMask(
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)
        )

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<EventTap>.fromOpaque(refcon).takeUnretainedValue()

            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if me.enabled, let tap = me.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            guard me.enabled else { return Unmanaged.passUnretained(event) }

            let flags = event.flags
            let code = event.getIntegerValueField(.keyboardEventKeycode)

            if type == .flagsChanged {
                if code == 61 {
                    if let m = rightOptionToShift(keyCode: code, flags: flags) {
                        event.flags = m.flags
                        event.setIntegerValueField(.keyboardEventKeycode, value: m.keyCode)
                        if me.debug { log("FLAG 右Option -> Shift [\(modifierLabels(m.flags))]") }
                    }
                    return Unmanaged.passUnretained(event)
                }
                if code == 62 { me.state.rightControl = flags.contains(.maskControl) }
                me.state.command = flags.contains(.maskCommand)
                me.state.option = flags.contains(.maskAlternate)
                if me.debug {
                    log("FLAG keyCode=\(code) flags=0x\(String(flags.rawValue, radix: 16)) [\(modifierLabels(flags))]")
                }
                return Unmanaged.passUnretained(event)
            }
            guard type == .keyDown || type == .keyUp else {
                return Unmanaged.passUnretained(event)
            }

            if !me.sawKey { me.sawKey = true; log("[tap 已收到键盘事件]") }

            let frontID: String? = (code == 2) ? frontmostBundleID() : nil
            let action = remap(keyCode: code, flags: flags, state: me.state,
                               cmdOnly: me.cmdOnly, frontBundleID: frontID)
            if me.debug {
                log("KEY \(type == .keyDown ? "down" : "up  ") keyCode=\(code) flags=0x\(String(flags.rawValue, radix: 16)) [\(modifierLabels(flags))] -> \(describe(action))")
            }

            switch action {
            case .pass:
                return Unmanaged.passUnretained(event)
            case .replace(let k, let f):
                event.flags = f
                event.setIntegerValueField(.keyboardEventKeycode, value: k)
                if !me.sawRemap { me.sawRemap = true; log("[已执行改写]") }
                return Unmanaged.passUnretained(event)
            case .keySequence(let strokes):
                if type == .keyDown { postKeySequence(strokes) }
                return nil
            case .scroll(let dx, let dy):
                if type == .keyDown { postScroll(dx: dx, dy: dy) }
                return nil
            case .open(let url):
                if type == .keyDown { openURL(url) }
                return nil
            }
        }

        let location: CGEventTapLocation = useSession ? .cgSessionEventTap : .cghidEventTap
        guard let tap = CGEvent.tapCreate(
            tap: location,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        self.tap = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source!, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: enabled)
        log("  tap 已创建 (位置: \(useSession ? "Session" : "HID"))")
        return true
    }

    func setEnabled(_ on: Bool) {
        enabled = on
        if let tap = tap { CGEvent.tapEnable(tap: tap, enable: on) }
        log("  映射已\(on ? "启用" : "停用")")
    }
}
