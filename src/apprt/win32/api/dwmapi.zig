//! Translucent acrylic backdrop via the Desktop Window Manager. The renderer
//! already produces a background with `background-opacity` baked into the
//! framebuffer alpha; this tells the DWM to composite the window translucently
//! and render an acrylic blur behind it. Best-effort: on systems without the
//! backdrop attribute we fall back to the legacy accent policy, and on anything
//! older we silently stay opaque (matching the macOS apprt's behavior).
const std = @import("std");
const windows = std.os.windows;

const BOOL = windows.BOOL;
const HWND = windows.HWND;
const HRESULT = windows.HRESULT;
const HMODULE = windows.HMODULE;

const S_OK: HRESULT = 0;

// --- Win11 22H2+ system backdrop (documented) --------------------------------

pub const DWMWA_SYSTEMBACKDROP_TYPE: u32 = 38;
pub const DWMSBT_NONE: c_int = 1; // solid, no backdrop
pub const DWMSBT_TRANSIENTWINDOW: c_int = 3; // acrylic

extern "dwmapi" fn DwmSetWindowAttribute(
    hwnd: HWND,
    attribute: u32,
    value: *const anyopaque,
    size: u32,
) callconv(.winapi) HRESULT;

/// Frame margins; a width of -1 on all sides extends the glass frame across the
/// entire client area ("sheet of glass"), which makes the DWM composite the
/// client area with per-pixel alpha. Without this a GL window is composited
/// opaquely and the backbuffer alpha (background-opacity) is ignored.
pub const MARGINS = extern struct {
    left: c_int,
    right: c_int,
    top: c_int,
    bottom: c_int,
};

extern "dwmapi" fn DwmExtendFrameIntoClientArea(
    hwnd: HWND,
    margins: *const MARGINS,
) callconv(.winapi) HRESULT;

// --- Pre-22H2 fallback: undocumented accent policy ---------------------------

pub const ACCENT_DISABLED: c_int = 0;
pub const ACCENT_ENABLE_ACRYLICBLURBEHIND: c_int = 4;
pub const WCA_ACCENT_POLICY: u32 = 19;

pub const ACCENT_POLICY = extern struct {
    accent_state: c_int,
    accent_flags: c_int,
    /// 0xAABBGGRR — AA is the tint opacity, BBGGRR the tint color.
    gradient_color: u32,
    animation_id: c_int,
};

pub const WINDOWCOMPOSITIONATTRIBDATA = extern struct {
    attrib: u32,
    data: *anyopaque,
    size: usize,
};

const SetWindowCompositionAttributeFn = *const fn (
    HWND,
    *WINDOWCOMPOSITIONATTRIBDATA,
) callconv(.winapi) BOOL;

extern "kernel32" fn GetModuleHandleA(name: [*:0]const u8) callconv(.winapi) ?HMODULE;
extern "kernel32" fn GetProcAddress(
    module: HMODULE,
    name: [*:0]const u8,
) callconv(.winapi) ?*const fn () callconv(.winapi) void;

/// Enable or disable a translucent acrylic backdrop on the window. Tries the
/// documented Win11 22H2+ system-backdrop attribute first; if that is not
/// supported (older Windows returns a non-success HRESULT), falls back to the
/// undocumented accent policy. The acrylic blur radius is chosen by the DWM and
/// is not tunable per-window, so callers pass on/off only.
pub fn setAcrylic(hwnd: HWND, enable: bool) void {
    // Extend the glass frame across the whole client area so the DWM composites
    // it with per-pixel alpha; otherwise the GL backbuffer is treated as opaque
    // and background-opacity / the acrylic backdrop never show through.
    const margins: MARGINS = if (enable)
        .{ .left = -1, .right = -1, .top = -1, .bottom = -1 }
    else
        .{ .left = 0, .right = 0, .top = 0, .bottom = 0 };
    _ = DwmExtendFrameIntoClientArea(hwnd, &margins);

    var backdrop: c_int = if (enable) DWMSBT_TRANSIENTWINDOW else DWMSBT_NONE;
    if (DwmSetWindowAttribute(
        hwnd,
        DWMWA_SYSTEMBACKDROP_TYPE,
        &backdrop,
        @sizeOf(c_int),
    ) == S_OK) return;

    const module = GetModuleHandleA("user32.dll") orelse return;
    const proc = GetProcAddress(module, "SetWindowCompositionAttribute") orelse return;
    const set_attr: SetWindowCompositionAttributeFn = @ptrCast(proc);

    var accent: ACCENT_POLICY = .{
        .accent_state = if (enable) ACCENT_ENABLE_ACRYLICBLURBEHIND else ACCENT_DISABLED,
        .accent_flags = 0,
        // A non-zero tint opacity (AA) is required; a fully transparent tint on
        // Win10 forces opaque compositing and severe drag lag.
        .gradient_color = 0xA0000000,
        .animation_id = 0,
    };
    var data: WINDOWCOMPOSITIONATTRIBDATA = .{
        .attrib = WCA_ACCENT_POLICY,
        .data = &accent,
        .size = @sizeOf(ACCENT_POLICY),
    };
    _ = set_attr(hwnd, &data);
}
