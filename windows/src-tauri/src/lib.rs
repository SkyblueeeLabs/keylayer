//! KeyLayer Windows 版：Tauri v2 托盘应用。
//! 映射逻辑与 `spec/keybindings.json` 绑定，并与 macOS 版共享同一组回归用例。

use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

use tauri::{Manager, State, WebviewUrl, WebviewWindowBuilder};

#[cfg(windows)]
mod hook;

mod generated;

// 原始规格只在测试里读取（跑共享 40 项用例）；运行时逻辑走 generated.rs 的常量表。
#[cfg(test)]
use std::sync::OnceLock;
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
    autostart: bool,
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
            if generated::WHITELIST_PREFIXES
                .iter()
                .any(|p| lower.starts_with(p))
            {
                return ("pass".into(), false, false);
            }
        }
    }

    let shift = has("shift");
    let command = action == "line-start" || action == "line-end";
    (action, shift, command)
}

#[tauri::command]
fn get_status(app: tauri::AppHandle, state: State<'_, AppState>) -> Status {
    use tauri_plugin_autostart::ManagerExt;
    Status {
        enabled: state.enabled.load(Ordering::Relaxed),
        hook_ok: state.hook_ok.load(Ordering::Relaxed),
        autostart: app.autolaunch().is_enabled().unwrap_or(false),
    }
}

#[tauri::command]
fn set_enabled(on: bool, app: tauri::AppHandle, state: State<'_, AppState>) -> bool {
    state.enabled.store(on, Ordering::Relaxed);
    save_enabled(&app, on);
    on
}

#[tauri::command]
fn set_autostart(on: bool, app: tauri::AppHandle) -> Result<bool, String> {
    use tauri_plugin_autostart::ManagerExt;
    let autolaunch = app.autolaunch();
    let result = if on {
        autolaunch.enable()
    } else {
        autolaunch.disable()
    };
    result.map_err(|e| e.to_string())?;
    autolaunch.is_enabled().map_err(|e| e.to_string())
}

#[tauri::command]
fn resize_panel(app: tauri::AppHandle, height: f64) {
    if let Some(w) = app.get_webview_window("panel") {
        if let (Ok(size), Ok(scale)) = (w.inner_size(), w.scale_factor()) {
            let width = size.width as f64 / scale;
            let _ = w.set_size(tauri::LogicalSize::new(width, height.clamp(120.0, 900.0)));
        }
    }
}

#[tauri::command]
fn quit_app(app: tauri::AppHandle) {
    app.exit(0);
}

fn state_file(app: &tauri::AppHandle) -> Option<PathBuf> {
    app.path()
        .app_config_dir()
        .ok()
        .map(|d| d.join("state.json"))
}

fn load_enabled(app: &tauri::AppHandle) -> bool {
    let Some(path) = state_file(app) else {
        return true;
    };
    let Ok(raw) = std::fs::read_to_string(path) else {
        return true;
    };
    serde_json::from_str::<serde_json::Value>(&raw)
        .ok()
        .and_then(|v| v.get("enabled").and_then(|e| e.as_bool()))
        .unwrap_or(true)
}

fn save_enabled(app: &tauri::AppHandle, on: bool) {
    let Some(path) = state_file(app) else {
        return;
    };
    if let Some(dir) = path.parent() {
        let _ = std::fs::create_dir_all(dir);
    }
    let _ = std::fs::write(path, format!("{{\"enabled\":{on}}}"));
}

fn now_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

/// 点击托盘时把面板放到图标附近：默认在任务栏上方，任务栏在顶部时改到下方，
/// 最后用当前显示器边界夹取，兼顾 DPI 缩放与多显示器。
fn place_panel(w: &tauri::WebviewWindow, x: f64, y: f64) {
    let Ok(size) = w.outer_size() else {
        return;
    };
    let width = size.width as i32;
    let height = size.height as i32;
    let mut left = (x - width as f64 / 2.0).round() as i32;
    let mut top = (y - height as f64).round() as i32;

    if let Ok(monitors) = w.available_monitors() {
        let monitor = monitors.iter().find(|m| {
            let p = m.position();
            let s = m.size();
            x >= p.x as f64
                && x < (p.x + s.width as i32) as f64
                && y >= p.y as f64
                && y < (p.y + s.height as i32) as f64
        });
        if let Some(m) = monitor {
            let p = m.position();
            let s = m.size();
            let min_x = p.x + 8;
            let max_x = (p.x + s.width as i32 - width - 8).max(min_x);
            let min_y = p.y + 8;
            let max_y = (p.y + s.height as i32 - height - 8).max(min_y);
            if top < min_y {
                top = (y + 12.0).round() as i32;
            }
            left = left.clamp(min_x, max_x);
            top = top.clamp(min_y, max_y);
        }
    }

    let _ = w.set_position(tauri::PhysicalPosition::new(left, top));
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let enabled = Arc::new(AtomicBool::new(true));
    let hook_ok = Arc::new(AtomicBool::new(false));

    tauri::Builder::default()
        .plugin(tauri_plugin_autostart::init(
            tauri_plugin_autostart::MacosLauncher::LaunchAgent,
            None,
        ))
        .manage(AppState {
            enabled: enabled.clone(),
            hook_ok: hook_ok.clone(),
        })
        .invoke_handler(tauri::generate_handler![
            get_status,
            set_enabled,
            set_autostart,
            resize_panel,
            quit_app
        ])
        .setup(move |app| {
            enabled.store(load_enabled(app.handle()), Ordering::Relaxed);

            // 无边框浮窗：Windows 没有系统级 popover，用置顶无边框窗口模拟
            let _panel =
                WebviewWindowBuilder::new(app, "panel", WebviewUrl::App("index.html".into()))
                    .title("KeyLayer")
                    .inner_size(340.0, 470.0)
                    .resizable(false)
                    .decorations(false)
                    .transparent(true)
                    .shadow(false)
                    .always_on_top(true)
                    .skip_taskbar(true)
                    .visible(false)
                    .build()?;

            #[cfg(windows)]
            {
                use tauri::image::Image;
                use tauri::tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent};

                let icon = Image::from_bytes(include_bytes!("../icons/tray.png"))?;
                TrayIconBuilder::with_id("main")
                    .icon(icon)
                    .tooltip("KeyLayer")
                    .on_tray_icon_event(|tray, event| {
                        // Windows 上 Click 会在按下和抬起各发一次，只处理抬起，
                        // 否则一次点击会把面板「打开又关掉」。
                        if let TrayIconEvent::Click {
                            button: MouseButton::Left | MouseButton::Right,
                            button_state: MouseButtonState::Up,
                            position,
                            ..
                        } = event
                        {
                            // 点击托盘会让面板先失焦收起，同一次点击不再把它重新弹出
                            if now_ms().saturating_sub(LAST_HIDE_MS.load(Ordering::Relaxed)) < 300 {
                                return;
                            }
                            let app = tray.app_handle();
                            if let Some(w) = app.get_webview_window("panel") {
                                if w.is_visible().unwrap_or(false) {
                                    let _ = w.hide();
                                } else {
                                    place_panel(&w, position.x, position.y);
                                    LAST_SHOW_MS.store(now_ms(), Ordering::Relaxed);
                                    let _ = w.show();
                                    let _ = w.set_focus();
                                }
                            }
                        }
                    })
                    .build(app)?;

                hook::start(enabled.clone(), hook_ok.clone());
            }

            // 调试用：KEYLAYER_SHOW_PANEL=1 时启动即弹出面板，便于截图与 UI 验收
            if std::env::var_os("KEYLAYER_SHOW_PANEL").is_some() {
                if let Some(panel) = app.get_webview_window("panel") {
                    if let Ok(Some(monitor)) = panel.current_monitor() {
                        let p = monitor.position();
                        let s = monitor.size();
                        place_panel(
                            &panel,
                            (p.x + s.width as i32 - 180) as f64,
                            (p.y + s.height as i32 - 60) as f64,
                        );
                    }
                    LAST_SHOW_MS.store(now_ms(), Ordering::Relaxed);
                    let _ = panel.show();
                    let _ = panel.set_focus();
                }
            }
            Ok(())
        })
        .on_window_event(|window, event| {
            // 失焦自动收起，模拟 popover 的 transient 行为。
            // 两个保护：① 只有真正拿到过焦点才收起；② 显示后 400ms 内的失焦忽略，
            // 避免点击托盘时系统短暂抢走焦点导致面板「闪一下」。
            match event {
                tauri::WindowEvent::Focused(true) if window.label() == "panel" => {
                    PANEL_FOCUSED.store(true, Ordering::Relaxed);
                }
                tauri::WindowEvent::Focused(false)
                    if window.label() == "panel"
                        && PANEL_FOCUSED.load(Ordering::Relaxed)
                        && now_ms().saturating_sub(LAST_SHOW_MS.load(Ordering::Relaxed)) >= 400 =>
                {
                    PANEL_FOCUSED.store(false, Ordering::Relaxed);
                    LAST_HIDE_MS.store(now_ms(), Ordering::Relaxed);
                    let _ = window.hide();
                }
                _ => {}
            }
        })
        .run(tauri::generate_context!())
        .expect("KeyLayer 启动失败");
}

static LAST_HIDE_MS: AtomicU64 = AtomicU64::new(0);
static LAST_SHOW_MS: AtomicU64 = AtomicU64::new(0);
static PANEL_FOCUSED: AtomicBool = AtomicBool::new(false);

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

    #[test]
    fn right_modifier_keys_are_generated() {
        assert_eq!(generated::vk_to_key(165), "RightAlt");
        assert_eq!(generated::vk_to_key(163), "RightCtrl");
    }
}
