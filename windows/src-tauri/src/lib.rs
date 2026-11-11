//! KeyLayer Windows 版：Tauri v2 托盘应用。
//! 映射逻辑与 `spec/keybindings.json` 绑定，并与 macOS 版共享同一组回归用例。
//! 注意：Windows 专属部分（托盘/钩子）未能在 macOS 上编译验证，
//! 首次在 Windows 上 `cargo build` 时请按 `windows/README.md` 的清单调整。

use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc, OnceLock,
};
use tauri::{Manager, State, WebviewUrl, WebviewWindowBuilder};

#[cfg(windows)]
mod hook;

mod generated;

// 原始规格只在测试里读取（跑共享 40 项用例）；运行时逻辑走 generated.rs 的常量表。
#[cfg(test)]
static SPEC: OnceLock<serde_json::Value> = OnceLock::new();
#[cfg(test)]
fn spec() -> &'static serde_json::Value {
    SPEC.get_or_init(|| {
        serde_json::from_str(include_str!("../../../spec/keybindings.json"))
            .expect("spec/keybindings.json 不是合法 JSON")
    })
}

pub struct AppState {
    pub enabled: Arc<AtomicBool>,
    pub hook_ok: Arc<AtomicBool>,
}

#[derive(serde::Serialize)]
pub struct Status {
    enabled: bool,
    hook_ok: bool,
}

/// 平台无关的映射逻辑，与 `spec/verify.mjs` 的参考实现保持一致。
/// 返回 `(action, shift_preserved, needs_command)`。
pub fn remap(
    key: &str,
    mods: &[&str],
    held: &[&str],
    cmd_only: bool,
    front_app: Option<&str>,
    enabled: bool,
) -> (String, bool, bool) {
    if !enabled {
        return ("pass".into(), false, false);
    }
    let has = |m: &str| mods.contains(&m) || held.contains(&m);

    // 右 Ctrl + b/g：打开固定网址（AHK 的 >^ 前缀）
    if has("rightCtrl") {
        let a = match key {
            "b" => "open-url:baidu",
            "g" => "open-url:google",
            _ => "pass",
        };
        return (a.into(), false, false);
    }
    // 右 Alt 改 Shift（AHK 33 行 RAlt::Shift）
    if key == "RightAlt" {
        return ("shift-down".into(), false, false);
    }
    // Control 组合一律放行，避免误伤系统快捷键
    if has("ctrl") {
        return ("pass".into(), false, false);
    }

    let triggered = if cmd_only {
        has("cmd")
    } else {
        has("cmd") || has("alt")
    };
    if !triggered {
        return ("pass".into(), false, false);
    }

    let action = match generated::by_key(key).map(|b| b.action) {
        Some(a) => a.to_string(),
        None => return ("pass".into(), false, false),
    };

    // delete-line 在 VS Code 内放行原键（AHK 64 行 WinActive）
    if action == "delete-line" {
        if let Some(app) = front_app {
            let lower = app.to_ascii_lowercase();
            if generated::WHITELIST_PREFIXES.iter().any(|p| lower.starts_with(p)) {
                return ("pass".into(), false, false);
            }
        }
    }

    let shift = has("shift");
    let command = action == "line-start" || action == "line-end";
    (action, shift, command)
}

#[tauri::command]
fn get_status(state: State<'_, AppState>) -> Status {
    Status {
        enabled: state.enabled.load(Ordering::Relaxed),
        hook_ok: state.hook_ok.load(Ordering::Relaxed),
    }
}

#[tauri::command]
fn set_enabled(on: bool, state: State<'_, AppState>) {
    state.enabled.store(on, Ordering::Relaxed);
}

#[tauri::command]
fn set_autostart(_on: bool) {
    // TODO: 写入 HKCU\Software\Microsoft\Windows\CurrentVersion\Run
    // 或使用 Tauri 的 autostart 插件。当前为骨架，尚未实现。
}

#[tauri::command]
fn quit_app(app: tauri::AppHandle) {
    app.exit(0);
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let enabled = Arc::new(AtomicBool::new(true));
    let hook_ok = Arc::new(AtomicBool::new(false));

    tauri::Builder::default()
        .manage(AppState {
            enabled: enabled.clone(),
            hook_ok: hook_ok.clone(),
        })
        .invoke_handler(tauri::generate_handler![
            get_status,
            set_enabled,
            set_autostart,
            quit_app
        ])
        .setup(move |app| {
            // 无边框浮窗：Windows 没有系统级 popover，用置顶无边框窗口模拟
            let _panel = WebviewWindowBuilder::new(
                app,
                "panel",
                WebviewUrl::App("index.html".into()),
            )
            .title("KeyLayer")
            .inner_size(340.0, 500.0)
            .decorations(false)
            .always_on_top(true)
            .skip_taskbar(true)
            .visible(false)
            .build()?;

            #[cfg(windows)]
            {
                use tauri::image::Image;
                use tauri::tray::{MouseButton, TrayIconBuilder, TrayIconEvent};

                let icon = Image::from_bytes(include_bytes!("../icons/tray.png"))?;
                TrayIconBuilder::with_id("main")
                    .icon(icon)
                    .tooltip("KeyLayer")
                    .on_tray_icon_event(|tray, event| {
                        if let TrayIconEvent::Click {
                            button: MouseButton::Left,
                            ..
                        } = event
                        {
                            let app = tray.app_handle();
                            if let Some(w) = app.get_webview_window("panel") {
                                if w.is_visible().unwrap_or(false) {
                                    let _ = w.hide();
                                } else {
                                    // TODO: 按托盘图标位置与 DPI 定位窗口
                                    let _ = w.show();
                                    let _ = w.set_focus();
                                }
                            }
                        }
                    })
                    .build(app)?;

                hook::start(enabled.clone(), hook_ok.clone());
            }
            Ok(())
        })
        .on_window_event(|window, event| {
            // 失焦自动收起，模拟 popover 的 transient 行为
            if let tauri::WindowEvent::Focused(false) = event {
                if window.label() == "panel" {
                    let _ = window.hide();
                }
            }
        })
        .run(tauri::generate_context!())
        .expect("KeyLayer 启动失败");
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 直接跑共享规格里的 40 项用例，保证 Windows 实现与 macOS 行为一致。
    #[test]
    fn shared_spec_cases() {
        let cases = spec()["cases"].as_array().expect("cases 数组");
        for c in cases {
            let name = c["name"].as_str().unwrap_or("?");
            let key = c["key"].as_str().unwrap();
            let mods: Vec<&str> = c["mods"]
                .as_array()
                .map(|a| a.iter().filter_map(|v| v.as_str()).collect())
                .unwrap_or_default();
            let held: Vec<&str> = c["held"]
                .as_array()
                .map(|a| a.iter().filter_map(|v| v.as_str()).collect())
                .unwrap_or_default();
            let cmd_only = c["cmdOnly"].as_bool().unwrap_or(false);
            let front = c["frontApp"].as_str();
            let expect = c["expect"].as_str().unwrap();

            let (action, shift, _) = remap(key, &mods, &held, cmd_only, front, true);
            assert_eq!(action, expect, "用例失败: {name}");
            if let Some(want) = c["shift"].as_bool() {
                assert_eq!(shift, want, "Shift 保留不符: {name}");
            }
        }
    }

    #[test]
    fn disabled_passes_through() {
        assert_eq!(remap("i", &["alt"], &[], false, None, false).0, "pass");
    }
}
