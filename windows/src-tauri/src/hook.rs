//! Windows 全局键盘钩子 `WH_KEYBOARD_LL`。
//!
//! 这是按行为规格重建的实现，不是从 KeyMap.exe 反汇编得来的代码。
//! 所有合成事件都带 `dwExtraInfo` 标记，钩子据此跳过自身事件，避免递归改写。

#![cfg(windows)]

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, OnceLock};
use std::time::Duration;

use windows_sys::Win32::Foundation::{CloseHandle, LPARAM, LRESULT, WPARAM};
use windows_sys::Win32::System::LibraryLoader::GetModuleHandleW;
use windows_sys::Win32::System::Threading::{
    OpenProcess, QueryFullProcessImageNameW, PROCESS_NAME_WIN32, PROCESS_QUERY_LIMITED_INFORMATION,
};
use windows_sys::Win32::UI::Input::KeyboardAndMouse::{
    GetAsyncKeyState, SendInput, INPUT, INPUT_0, INPUT_KEYBOARD, INPUT_MOUSE, KEYBDINPUT,
    KEYEVENTF_EXTENDEDKEY, KEYEVENTF_KEYUP, MOUSEEVENTF_HWHEEL, MOUSEEVENTF_WHEEL, MOUSEINPUT,
    VK_BACK, VK_DOWN, VK_END, VK_HOME, VK_LCONTROL, VK_LEFT, VK_LMENU, VK_RCONTROL, VK_RIGHT,
    VK_RMENU, VK_SHIFT, VK_UP,
};
use windows_sys::Win32::UI::WindowsAndMessaging::{
    CallNextHookEx, DispatchMessageW, GetForegroundWindow, GetMessageW, GetWindowThreadProcessId,
    SetWindowsHookExW, TranslateMessage, UnhookWindowsHookEx, MSG, WH_KEYBOARD_LL,
};

const WM_KEYDOWN: u32 = 0x0100;
const WM_KEYUP: u32 = 0x0101;
const WM_SYSKEYDOWN: u32 = 0x0104;
const WM_SYSKEYUP: u32 = 0x0105;
const LLKHF_INJECTED: u32 = 0x10;

const WHEEL_DELTA: i32 = 120;
/// 合成事件的标记，钩子见到它就原样放行（自身事件不二次改写）。
const MAGIC: usize = 0x4B4C_5941; // "KLYA"
/// 个别键盘/驱动上报通用 Alt 而不是左右 Alt
const VK_ALT_GENERIC: u8 = 0x12;

#[repr(C)]
struct KbdLlHookStruct {
    vk_code: u32,
    scan_code: u32,
    flags: u32,
    time: u32,
    extra: usize,
}

static ENABLED: OnceLock<Arc<AtomicBool>> = OnceLock::new();
static HOOK_OK: OnceLock<Arc<AtomicBool>> = OnceLock::new();
/// 右 Alt 正在充当 Shift（按下时吞掉原键并合成 Shift）。
static RALT_ACTIVE: AtomicBool = AtomicBool::new(false);
/// 左 Alt 被钩子暂扣中：先不发给目标应用，等确定是映射组合还是普通 Alt 组合。
static ALT_HELD: AtomicBool = AtomicBool::new(false);
/// 已把 Alt 补发给目标应用（非映射组合需要）。
static ALT_EMITTED: AtomicBool = AtomicBool::new(false);
/// 本次按住 Alt 期间命中过映射键，松开 Alt 时不再补一次「单独 Alt」。
static ALT_CONSUMED: AtomicBool = AtomicBool::new(false);
/// 仅用于自动化测试：允许处理非本程序合成的注入事件。
static ALLOW_INJECTED: AtomicBool = AtomicBool::new(false);
/// 仅用于调试：逐键记录 vk / 修饰键 / 动作（含放行）。
static DEBUG_KEYS: AtomicBool = AtomicBool::new(false);

pub fn start(enabled: Arc<AtomicBool>, hook_ok: Arc<AtomicBool>) {
    let _ = ENABLED.set(enabled);
    let _ = HOOK_OK.set(hook_ok);
    ALLOW_INJECTED.store(
        std::env::var_os("KEYLAYER_ALLOW_INJECTED").is_some(),
        Ordering::Relaxed,
    );
    DEBUG_KEYS.store(
        std::env::var_os("KEYLAYER_DEBUG_KEYS").is_some(),
        Ordering::Relaxed,
    );
    std::thread::spawn(|| unsafe {
        loop {
            let hmod = GetModuleHandleW(std::ptr::null());
            let hook = SetWindowsHookExW(WH_KEYBOARD_LL, Some(callback), hmod, 0);
            let ok = !hook.is_null();
            if let Some(flag) = HOOK_OK.get() {
                flag.store(ok, Ordering::Relaxed);
            }
            if !ok {
                debug_log("hook install failed, retrying");
                std::thread::sleep(Duration::from_secs(2));
                continue;
            }
            debug_log("hook installed");

            // 低级钩子必须由安装它的线程跑消息泵
            let mut msg: MSG = std::mem::zeroed();
            loop {
                let r = GetMessageW(&mut msg, std::ptr::null_mut(), 0, 0);
                if r <= 0 {
                    break;
                }
                TranslateMessage(&msg);
                DispatchMessageW(&msg);
            }

            UnhookWindowsHookEx(hook);
            if let Some(flag) = HOOK_OK.get() {
                flag.store(false, Ordering::Relaxed);
            }
            debug_log("hook message loop ended, reinstalling");
            std::thread::sleep(Duration::from_secs(1));
        }
    });
}

fn next(code: i32, wparam: WPARAM, lparam: LPARAM) -> LRESULT {
    unsafe { CallNextHookEx(std::ptr::null_mut(), code, wparam, lparam) }
}

unsafe extern "system" fn callback(code: i32, wparam: WPARAM, lparam: LPARAM) -> LRESULT {
    if code < 0 {
        return next(code, wparam, lparam);
    }
    let kb = &*(lparam as *const KbdLlHookStruct);
    if kb.extra == MAGIC {
        return next(code, wparam, lparam);
    }
    if (kb.flags & LLKHF_INJECTED) != 0 && !ALLOW_INJECTED.load(Ordering::Relaxed) {
        return next(code, wparam, lparam);
    }

    let msg = wparam as u32;
    let is_down = msg == WM_KEYDOWN || msg == WM_SYSKEYDOWN;
    let is_up = msg == WM_KEYUP || msg == WM_SYSKEYUP;
    if !(is_down || is_up) {
        return next(code, wparam, lparam);
    }

    let enabled = ENABLED
        .get()
        .map(|e| e.load(Ordering::Relaxed))
        .unwrap_or(false);
    if !enabled {
        if RALT_ACTIVE.swap(false, Ordering::Relaxed) {
            send(&[key_input(VK_SHIFT, true)]);
        }
        // 暂扣的 Alt 交还给系统，后续物理 Alt 松开由系统处理
        let held = ALT_HELD.swap(false, Ordering::Relaxed);
        let emitted = ALT_EMITTED.swap(false, Ordering::Relaxed);
        if held && !emitted {
            send(&[key_input(VK_LMENU, false)]);
        }
        return next(code, wparam, lparam);
    }

    let vk = kb.vk_code as u8;
    if vk == VK_RMENU as u8 {
        // AHK 33 行 RAlt::Shift：吞掉右 Alt，改成 Shift
        if is_down {
            if !RALT_ACTIVE.swap(true, Ordering::Relaxed) {
                send(&[key_input(VK_SHIFT, false)]);
            }
        } else if RALT_ACTIVE.swap(false, Ordering::Relaxed) {
            send(&[key_input(VK_SHIFT, true)]);
        }
        debug_log(if is_down {
            "RAlt down -> Shift down"
        } else {
            "RAlt up -> Shift up"
        });
        return 1;
    }

    // 左 Alt 是触发键：先暂扣，映射命中时目标应用完全看不到 Alt，
    // 否则目标会进入菜单模式，把随后合成的方向键 / Home 吃掉。
    if vk == VK_LMENU as u8 || vk == VK_ALT_GENERIC {
        if is_down {
            ALT_HELD.store(true, Ordering::Relaxed);
            ALT_EMITTED.store(false, Ordering::Relaxed);
            ALT_CONSUMED.store(false, Ordering::Relaxed);
        } else if ALT_HELD.swap(false, Ordering::Relaxed) {
            if ALT_EMITTED.swap(false, Ordering::Relaxed) {
                send(&[key_input(VK_LMENU, true)]);
            } else if !ALT_CONSUMED.swap(false, Ordering::Relaxed) {
                // 单独按了一下 Alt：补一次轻点，保留系统菜单栏行为
                send(&[key_input(VK_LMENU, false), key_input(VK_LMENU, true)]);
            }
        }
        debug_log(&format!(
            "LAlt {} vk={vk} held={} emitted={} consumed={}",
            if is_down { "down" } else { "up" },
            ALT_HELD.load(Ordering::Relaxed),
            ALT_EMITTED.load(Ordering::Relaxed),
            ALT_CONSUMED.load(Ordering::Relaxed)
        ));
        return 1;
    }

    let key = vk_to_key(vk);
    let alt_held = ALT_HELD.load(Ordering::Relaxed);
    let shift = key_down(VK_SHIFT);
    let ctrl_left = key_down(VK_LCONTROL);
    let ctrl_right = key_down(VK_RCONTROL);

    let mut mods: Vec<&str> = Vec::with_capacity(4);
    if alt_held {
        mods.push("alt");
    }
    if shift {
        mods.push("shift");
    }
    if ctrl_left || ctrl_right {
        mods.push("ctrl");
    }
    if ctrl_right {
        mods.push("rightCtrl");
    }

    // 白名单只在 delete-line 上生效，按需查询前台进程，避免每个按键都开进程句柄
    let front = if key == "d" {
        foreground_process_name()
    } else {
        None
    };

    let (action, keep_shift, _needs_command) =
        crate::remap(key, &mods, &[], false, front.as_deref(), enabled);

    if DEBUG_KEYS.load(Ordering::Relaxed) {
        debug_log(&format!(
            "event vk={vk} down={is_down} mods={mods:?} action={action}"
        ));
    }

    if action == "pass" {
        // 非映射组合（Alt+Tab / Alt+F4 / VS Code 白名单放行等）：
        // 在放行前把暂扣的 Alt 补发给目标应用
        if is_down && alt_held && !ALT_EMITTED.swap(true, Ordering::Relaxed) {
            send(&[key_input(VK_LMENU, false)]);
        }
        return next(code, wparam, lparam);
    }

    if is_down && alt_held {
        ALT_CONSUMED.store(true, Ordering::Relaxed);
    }
    let alt_emitted = ALT_EMITTED.load(Ordering::Relaxed);

    debug_log(&format!(
        "key={key} down={is_down} mods={mods:?} altEmitted={alt_emitted} front={front:?} action={action} shift={keep_shift}"
    ));

    // 动作只在 keyDown 执行一次；配对 keyUp 吞掉，避免按键状态卡住
    if is_down {
        execute(&action, keep_shift, alt_emitted);
    }
    1 // 吞掉原事件
}

// Windows 虚拟键码 → 逻辑键名，由 spec/keybindings.json 生成
fn vk_to_key(vk: u8) -> &'static str {
    crate::generated::vk_to_key(vk)
}

fn key_down(vk: u16) -> bool {
    unsafe { (GetAsyncKeyState(vk as i32) as u16 & 0x8000) != 0 }
}

fn execute(action: &str, keep_shift: bool, alt_emitted: bool) {
    match action {
        "arrow-up" => press(VK_UP, keep_shift, alt_emitted),
        "arrow-down" => press(VK_DOWN, keep_shift, alt_emitted),
        "arrow-left" => press(VK_LEFT, keep_shift, alt_emitted),
        "arrow-right" => press(VK_RIGHT, keep_shift, alt_emitted),
        "line-start" => press(VK_HOME, keep_shift, alt_emitted),
        "line-end" => press(VK_END, keep_shift, alt_emitted),
        "delete-line" => delete_line(alt_emitted),
        "scroll-down" => wheel(false, -3, alt_emitted),
        "scroll-up" => wheel(false, 3, alt_emitted),
        "scroll-left" => wheel(true, -3, alt_emitted),
        "scroll-right" => wheel(true, 3, alt_emitted),
        // 动作名带的是 baidu/google，生成表按按键 b/g 索引
        "open-url:baidu" => open_url("b"),
        "open-url:google" => open_url("g"),
        _ => {}
    }
}

fn open_url(key: &str) {
    if let Some((_, _, url)) = crate::generated::URL_ACTIONS
        .iter()
        .find(|(k, _, _)| *k == key)
    {
        let _ = open::that(url);
    }
}

fn is_extended_key(vk: u16) -> bool {
    matches!(vk, VK_UP | VK_DOWN | VK_LEFT | VK_RIGHT | VK_HOME | VK_END)
}

fn key_input(vk: u16, up: bool) -> INPUT {
    let mut flags = if up { KEYEVENTF_KEYUP } else { 0 };
    if is_extended_key(vk) {
        flags |= KEYEVENTF_EXTENDEDKEY;
    }
    INPUT {
        r#type: INPUT_KEYBOARD,
        Anonymous: INPUT_0 {
            ki: KEYBDINPUT {
                wVk: vk,
                wScan: 0,
                dwFlags: flags,
                time: 0,
                dwExtraInfo: MAGIC,
            },
        },
    }
}

fn wheel_input(horizontal: bool, amount: i32) -> INPUT {
    INPUT {
        r#type: INPUT_MOUSE,
        Anonymous: INPUT_0 {
            mi: MOUSEINPUT {
                dx: 0,
                dy: 0,
                // 负数滚轮按补码写入 u32
                mouseData: (amount * WHEEL_DELTA) as u32,
                dwFlags: if horizontal {
                    MOUSEEVENTF_HWHEEL
                } else {
                    MOUSEEVENTF_WHEEL
                },
                time: 0,
                dwExtraInfo: MAGIC,
            },
        },
    }
}

fn send(inputs: &[INPUT]) {
    if inputs.is_empty() {
        return;
    }
    let sent = unsafe {
        SendInput(
            inputs.len() as u32,
            inputs.as_ptr(),
            std::mem::size_of::<INPUT>() as i32,
        )
    };
    if sent as usize != inputs.len() {
        let err = std::io::Error::last_os_error();
        debug_log(&format!(
            "SendInput sent {sent}/{} size={} err={err}",
            inputs.len(),
            std::mem::size_of::<INPUT>()
        ));
    }
}

/// 合成一次按键。触发用的 Alt 必须先「松开」，否则目标应用收到的是 Alt+方向键；
/// 物理 Alt 仍按着时在结尾补一次 Alt 按下，否则后续 Alt+字母不会再次触发。
fn press(vk: u16, keep_shift: bool, alt_emitted: bool) {
    let mut inputs: Vec<INPUT> = Vec::with_capacity(6);
    if alt_emitted {
        inputs.push(key_input(VK_LMENU, true));
    }
    let add_shift = keep_shift && !key_down(VK_SHIFT);
    if add_shift {
        inputs.push(key_input(VK_SHIFT, false));
    }
    inputs.push(key_input(vk, false));
    inputs.push(key_input(vk, true));
    if add_shift {
        inputs.push(key_input(VK_SHIFT, true));
    }
    if alt_emitted {
        inputs.push(key_input(VK_LMENU, false));
    }
    send(&inputs);
}

/// 来自 AHK 脚本 67 行：{Home}+{End}+{Right}{BS}{Home}
fn delete_line(alt_emitted: bool) {
    let add_shift = !key_down(VK_SHIFT);
    let mut inputs: Vec<INPUT> = Vec::with_capacity(14);
    if alt_emitted {
        inputs.push(key_input(VK_LMENU, true));
    }
    inputs.push(key_input(VK_HOME, false));
    inputs.push(key_input(VK_HOME, true));
    if add_shift {
        inputs.push(key_input(VK_SHIFT, false));
    }
    inputs.push(key_input(VK_END, false));
    inputs.push(key_input(VK_END, true));
    inputs.push(key_input(VK_RIGHT, false));
    inputs.push(key_input(VK_RIGHT, true));
    if add_shift {
        inputs.push(key_input(VK_SHIFT, true));
    }
    inputs.push(key_input(VK_BACK, false));
    inputs.push(key_input(VK_BACK, true));
    inputs.push(key_input(VK_HOME, false));
    inputs.push(key_input(VK_HOME, true));
    if alt_emitted {
        inputs.push(key_input(VK_LMENU, false));
    }
    send(&inputs);
}

/// 滚轮前同样先松开 Alt，避免浏览器等应用把 Alt+滚轮当成缩放/自定义快捷键。
fn wheel(horizontal: bool, amount: i32, alt_emitted: bool) {
    let mut inputs: Vec<INPUT> = Vec::with_capacity(3);
    if alt_emitted {
        inputs.push(key_input(VK_LMENU, true));
    }
    inputs.push(wheel_input(horizontal, amount));
    if alt_emitted {
        inputs.push(key_input(VK_LMENU, false));
    }
    send(&inputs);
}

/// 前台窗口的进程文件名，例如 `Code.exe`；用于 VS Code 白名单。
fn foreground_process_name() -> Option<String> {
    unsafe {
        let hwnd = GetForegroundWindow();
        if hwnd.is_null() {
            return None;
        }
        let mut pid: u32 = 0;
        GetWindowThreadProcessId(hwnd, &mut pid);
        if pid == 0 {
            return None;
        }
        let handle = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, 0, pid);
        if handle.is_null() {
            return None;
        }
        let mut buf = [0u16; 512];
        let mut len = buf.len() as u32;
        let ok = QueryFullProcessImageNameW(handle, PROCESS_NAME_WIN32, buf.as_mut_ptr(), &mut len);
        CloseHandle(handle);
        if ok == 0 || len == 0 {
            return None;
        }
        let path = String::from_utf16_lossy(&buf[..len as usize]);
        path.rsplit(['\\', '/']).next().map(|s| s.to_string())
    }
}

fn debug_log(msg: &str) {
    let Some(path) = std::env::var_os("KEYLAYER_DEBUG_LOG") else {
        return;
    };
    use std::io::Write;
    if let Ok(mut f) = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(path)
    {
        let _ = writeln!(f, "[{:?}] {}", std::process::id(), msg);
    }
}
