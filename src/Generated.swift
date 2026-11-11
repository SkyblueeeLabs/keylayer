// 自动生成 — 请勿手动编辑
// 来源: spec/keybindings.json
// 重新生成: npm run spec
// spec-hash: c44150cfb3a7

struct GenBinding {
    let key: String
    let macKeyCode: Int64
    let winVK: Int
    let action: String
    let label: String
    let group: String
}

enum Generated {
    static let bindings: [GenBinding] = [
        GenBinding(key: "i", macKeyCode: 34, winVK: 73, action: "arrow-up", label: "↑", group: "direction"),
        GenBinding(key: "j", macKeyCode: 38, winVK: 74, action: "arrow-left", label: "←", group: "direction"),
        GenBinding(key: "k", macKeyCode: 40, winVK: 75, action: "arrow-down", label: "↓", group: "direction"),
        GenBinding(key: "l", macKeyCode: 37, winVK: 76, action: "arrow-right", label: "→", group: "direction"),
        GenBinding(key: "u", macKeyCode: 32, winVK: 85, action: "line-start", label: "行首", group: "direction"),
        GenBinding(key: "o", macKeyCode: 31, winVK: 79, action: "line-end", label: "行尾", group: "direction"),
        GenBinding(key: "d", macKeyCode: 2, winVK: 68, action: "delete-line", label: "删整行", group: "action"),
        GenBinding(key: "h", macKeyCode: 4, winVK: 72, action: "scroll-down", label: "滚↓", group: "scroll"),
        GenBinding(key: "y", macKeyCode: 16, winVK: 89, action: "scroll-up", label: "滚↑", group: "scroll"),
        GenBinding(key: "n", macKeyCode: 45, winVK: 78, action: "scroll-left", label: "滚←", group: "scroll"),
        GenBinding(key: "m", macKeyCode: 46, winVK: 77, action: "scroll-right", label: "滚→", group: "scroll"),
    ]

    static let actionKeyCodes: [String: (mac: Int64, win: Int, needsCommand: Bool)] = [
        "arrow-up": (126, 38, false),
        "arrow-down": (125, 40, false),
        "arrow-left": (123, 37, false),
        "arrow-right": (124, 39, false),
        "line-start": (123, 36, true),
        "line-end": (124, 35, true),
    ]

    static let urlActions: [(mac: Int64, win: Int, url: String)] = [
        (11, 66, "https://www.baidu.com"),
        (5, 71, "https://www.google.com"),
    ]

    static let vscodeBundleIDs: Set<String> = [
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.visualstudio.code.oss",
    ]

    static let keyCapRows: [[(id: String, label: String, desc: String, group: String)]] = [
        [("u", "U", "行首", "direction"), ("i", "I", "↑", "direction"), ("o", "O", "行尾", "direction")],
        [("j", "J", "←", "direction"), ("k", "K", "↓", "direction"), ("l", "L", "→", "direction")],
        [("d", "D", "删整行", "action"), ("h", "H", "滚↓", "scroll"), ("y", "Y", "滚↑", "scroll")],
        [("n", "N", "滚←", "scroll"), ("m", "M", "滚→", "scroll"), ("ralt", "右Alt", "⇧", "modifier")],
    ]

    static func macBinding(_ code: Int64) -> GenBinding? {
        bindings.first { $0.macKeyCode == code }
    }
    static func winBinding(_ vk: Int) -> GenBinding? {
        bindings.first { $0.winVK == vk }
    }
}
