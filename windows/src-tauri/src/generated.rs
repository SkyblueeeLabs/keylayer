// 自动生成 — 请勿手动编辑
// 来源: spec/keybindings.json
// 重新生成: npm run spec
// spec-hash: c44150cfb3a7

#[derive(Clone, Copy)]
pub struct Binding {
    pub key: &'static str,
    pub win_vk: u8,
    pub mac_key: i64,
    pub action: &'static str,
    pub label: &'static str,
    pub group: &'static str,
}

pub static BINDINGS: &[Binding] = &[
    Binding { key: "i", win_vk: 73, mac_key: 34, action: "arrow-up", label: "↑", group: "direction" },
    Binding { key: "j", win_vk: 74, mac_key: 38, action: "arrow-left", label: "←", group: "direction" },
    Binding { key: "k", win_vk: 75, mac_key: 40, action: "arrow-down", label: "↓", group: "direction" },
    Binding { key: "l", win_vk: 76, mac_key: 37, action: "arrow-right", label: "→", group: "direction" },
    Binding { key: "u", win_vk: 85, mac_key: 32, action: "line-start", label: "行首", group: "direction" },
    Binding { key: "o", win_vk: 79, mac_key: 31, action: "line-end", label: "行尾", group: "direction" },
    Binding { key: "d", win_vk: 68, mac_key: 2, action: "delete-line", label: "删整行", group: "action" },
    Binding { key: "h", win_vk: 72, mac_key: 4, action: "scroll-down", label: "滚↓", group: "scroll" },
    Binding { key: "y", win_vk: 89, mac_key: 16, action: "scroll-up", label: "滚↑", group: "scroll" },
    Binding { key: "n", win_vk: 78, mac_key: 45, action: "scroll-left", label: "滚←", group: "scroll" },
    Binding { key: "m", win_vk: 77, mac_key: 46, action: "scroll-right", label: "滚→", group: "scroll" },
];

pub fn by_key(key: &str) -> Option<&'static Binding> {
    BINDINGS.iter().find(|b| b.key == key)
}

pub fn by_win_vk(vk: u8) -> Option<&'static Binding> {
    BINDINGS.iter().find(|b| b.win_vk == vk)
}

pub static URL_ACTIONS: &[(&str, u8, &str)] = &[
    ("b", 66, "https://www.baidu.com"),
    ("g", 71, "https://www.google.com"),
];

pub static WHITELIST_PREFIXES: &[&str] = &[
    "code",
];

pub fn vk_to_key(vk: u8) -> &'static str {
    match vk {
        73 => "i",
        74 => "j",
        75 => "k",
        76 => "l",
        85 => "u",
        79 => "o",
        68 => "d",
        72 => "h",
        89 => "y",
        78 => "n",
        77 => "m",
        66 => "b",
        71 => "g",
        _ => ""
    }
}
