//! Windows 全局键盘钩子 `WH_KEYBOARD_LL`。
//!
//! ⚠️ 这部分 FFI **未在 macOS 上编译验证**。首次在 Windows 上 `cargo build`
//! 若报类型/签名错误，按 `windows/README.md` 的「首次构建检查清单」调整。
//! 这是从行为规格重建的实现，不是从 KeyMap.exe 反汇编得来的代码。

#![cfg(windows)]

use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc, OnceLock,
};
use windows_sys::Win32::{
    Foundation::{LPARAM, LRESULT, WPARAM},
    UI::Input::KeyboardAndMouse::{
        keybd_event, mouse_event, GetAsyncKeyState, KEYEVENTF_KEYUP,
    },
    UI::WindowsAndMessaging::{
        CallNextHookEx, DispatchMessageW, GetMessageW, SetWindowsHookExW, TranslateMessage, MSG,
    },
};

// 常量自定义，避免依赖 windows-sys 各版本 feature 差异
const WH_KEYBOARD_LL: i32 = 13;
const WM_KEYDOWN: u32 = 0x0100;
const WM_KEYUP: u32 = 0x0101;
const WM_SYSKEYDOWN: u32 = 0x0104;
const WM_SYSKEYUP: u32 = 0x0105;
const LLKHF_INJECTED: u32 = 0x10;
const LLKHF_ALTDOWN: u32 = 0x20;

const VK_BACK: u8 = 0x08;
const VK_SHIFT: u8 = 0x10;
const VK_CONTROL: u8 = 0x11;
const VK_MENU: u8 = 0x12;
const VK_HOME: u8 = 0x24;
const VK_END: u8 = 0x23;
const VK_LEFT: u8 = 0x25;
const VK_UP: u8 = 0x26;
const VK_RIGHT: u8 = 0x27;
const VK_DOWN: u8 = 0x28;

const MOUSEEVENTF_WHEEL: u32 = 0x0800;
const MOUSEEVENTF_HWHEEL: u32 = 0x1000;
const WHEEL_DELTA: i32 = 120;

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
static SENDING: AtomicBool = AtomicBool::new(false);

pub fn start(enabled: Arc<AtomicBool>, hook_ok: Arc<AtomicBool>) {
    let _ = ENABLED.set(enabled);
    let _ = HOOK_OK.set(hook_ok);
    std::thread::spawn(|| unsafe {
        let hook = SetWindowsHookExW(WH_KEYBOARD_LL, Some(callback), std::ptr::null_mut(), 0);
        // 若 windows-sys 把 HHOOK 定义为整数而非指针，把 is_null() 改成 `hook == 0`
        let ok = !hook.is_null();
        if let Some(flag) = HOOK_OK.get() {
            flag.store(ok, Ordering::Relaxed);
        }
        let mut msg: MSG = std::mem::zeroed();
        // 低级钩子需要一个消息泵
        while GetMessageW(&mut msg, std::ptr::null_mut(), 0, 0) > 0 {
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
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
    // 跳过我们自己合成的事件，避免递归改写
    if SENDING.load(Ordering::Relaxed) {
        return next(code, wparam, lparam);
    }
    let kb = &*(lparam as *const KbdLlHookStruct);
    if (kb.flags & LLKHF_INJECTED) != 0 {
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
        return next(code, wparam, lparam);
    }

    let vk = kb.vk_code as u8;
    let key = vk_to_key(vk);
    let alt = (kb.flags & LLKHF_ALTDOWN) != 0;
    let shift = GetAsyncKeyState(VK_SHIFT as i32) < 0;
    let ctrl = GetAsyncKeyState(VK_CONTROL as i32) < 0;

    let mut mods: Vec<&str> = Vec::new();
    if alt { mods.push("alt"); }
    if shift { mods.push("shift"); }
    if ctrl { mods.push("ctrl"); }

    // TODO: 用 GetAsyncKeyState(VK_RMENU/VK_RCONTROL) 区分左右 Alt/Ctrl，
    //       以支撑「右 Alt→Shift」「右 Ctrl+B/G 打开网页」两条规则。
    // TODO: 用 GetForegroundWindow + QueryFullProcessImageNameW 取前台进程名，
    //       传给 remap 的 front_app 参数以启用 VS Code 白名单。

    let (action, keep_shift, _needs_command) =
        crate::remap(key, &mods, &[], false, None, enabled);

    if action == "pass" {
        return next(code, wparam, lparam);
    }

    // 动作只在 keyDown 执行一次；配对 keyUp 吞掉，避免按键状态卡住
    if is_down {
        execute(&action, keep_shift);
    }
    1 // 吞掉原事件
}

// Windows 虚拟键码 → 逻辑键名，由 spec/keybindings.json 生成
fn vk_to_key(vk: u8) -> &'static str {
    crate::generated::vk_to_key(vk)
}

fn execute(action: &str, keep_shift: bool) {
    SENDING.store(true, Ordering::Relaxed);
    match action {
        "arrow-up" => tap(VK_UP, keep_shift),
        "arrow-down" => tap(VK_DOWN, keep_shift),
        "arrow-left" => tap(VK_LEFT, keep_shift),
        "arrow-right" => tap(VK_RIGHT, keep_shift),
        "line-start" => tap(VK_HOME, keep_shift),
        "line-end" => tap(VK_END, keep_shift),
        "delete-line" => delete_line(),
        "scroll-down" => wheel(false, -3),
        "scroll-up" => wheel(false, 3),
        "scroll-left" => wheel(true, -3),
        "scroll-right" => wheel(true, 3),
        "open-url:baidu" => { let _ = open::that("https://www.baidu.com"); }
        "open-url:google" => { let _ = open::that("https://www.google.com"); }
        _ => {}
    }
    SENDING.store(false, Ordering::Relaxed);
}

/// 合成一次按键。触发用的 Alt 必须先「松开」，否则目标应用收到的是 Alt+方向键。
/// ⚠️ 这里不主动恢复 Alt 状态：用户物理仍按着 Alt，恢复动作可能造成修饰键状态
/// 与物理状态不一致。是否需要恢复、以及长按重复的行为，请在真机上实测后调整。
unsafe fn tap(vk: u8, keep_shift: bool) {
    keybd_event(VK_MENU, 0, KEYEVENTF_KEYUP, 0);
    if keep_shift {
        keybd_event(VK_SHIFT, 0, 0, 0);
    }
    keybd_event(vk, 0, 0, 0);
    keybd_event(vk, 0, KEYEVENTF_KEYUP, 0);
    if keep_shift {
        keybd_event(VK_SHIFT, 0, KEYEVENTF_KEYUP, 0);
    }
}

/// 来自 AHK 脚本 67 行：{Home}+{End}+{Right}{BS}{Home}
unsafe fn delete_line() {
    tap(VK_HOME, false);
    tap(VK_END, true);
    tap(VK_RIGHT, true);
    tap(VK_BACK, false);
    tap(VK_HOME, false);
}

unsafe fn wheel(horizontal: bool, amount: i32) {
    let flags = if horizontal { MOUSEEVENTF_HWHEEL } else { MOUSEEVENTF_WHEEL };
    // dwData 是 u32，负值用 as u32 换算成补码传递
    mouse_event(flags, 0, 0, (amount * WHEEL_DELTA) as u32, 0);
}
