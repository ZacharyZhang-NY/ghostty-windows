//! A thin owner of a Win32 top-level window: class registration, creation,
//! destruction and the few geometry/title helpers the surface needs. The window
//! procedure is supplied by the caller (`window_proc.zig`) so this module stays
//! free of Ghostty-core dependencies.
const std = @import("std");
const windows = std.os.windows;
const user32 = @import("api/user32.zig");
const dwmapi = @import("api/dwmapi.zig");
const apprt = @import("../../apprt.zig");

const log = std.log.scoped(.win32_window);

pub const Error = error{
    RegisterClassFailed,
    CreateWindowFailed,
};

/// UTF-16 window class name, registered once per process.
pub const class_name = std.unicode.utf8ToUtf16LeStringLiteral("GhosttySurface");

var registered: bool = false;

/// Register the window class. Idempotent. The cursor is the standard arrow;
/// background is null so we never flicker a GDI fill behind the GL surface.
pub fn register(
    instance: windows.HINSTANCE,
    wndproc: user32.WNDPROC,
) Error!void {
    if (registered) return;

    const wcx: user32.WNDCLASSEXW = .{
        .cbSize = @sizeOf(user32.WNDCLASSEXW),
        .style = user32.CS_HREDRAW | user32.CS_VREDRAW | user32.CS_OWNDC,
        .lpfnWndProc = wndproc,
        .cbClsExtra = 0,
        .cbWndExtra = 0,
        .hInstance = instance,
        .hIcon = null,
        .hCursor = user32.LoadCursorW(null, user32.IDC_ARROW),
        .hbrBackground = null,
        .lpszMenuName = null,
        .lpszClassName = class_name,
        .hIconSm = null,
    };

    if (user32.RegisterClassExW(&wcx) == 0) return error.RegisterClassFailed;
    registered = true;
}

/// Create a top-level window sized so its CLIENT area is `width` x `height`
/// logical pixels at the system DPI. `param` is delivered to the window
/// procedure's WM_NCCREATE via the CREATESTRUCT to bind the owning surface.
pub fn create(
    instance: windows.HINSTANCE,
    title: [:0]const u16,
    width: i32,
    height: i32,
    param: ?*anyopaque,
) Error!windows.HWND {
    const style = user32.WS_OVERLAPPEDWINDOW |
        user32.WS_CLIPSIBLINGS |
        user32.WS_CLIPCHILDREN;

    // Expand the client size to the full window size for the default DPI; the
    // window proc re-adjusts on WM_DPICHANGED for per-monitor correctness.
    var rect: windows.RECT = .{ .left = 0, .top = 0, .right = width, .bottom = height };
    _ = user32.AdjustWindowRectExForDpi(
        &rect,
        style,
        windows.FALSE,
        0,
        user32.USER_DEFAULT_SCREEN_DPI,
    );

    return user32.CreateWindowExW(
        0,
        class_name,
        title.ptr,
        style,
        user32.CW_USEDEFAULT,
        user32.CW_USEDEFAULT,
        rect.right - rect.left,
        rect.bottom - rect.top,
        null,
        null,
        instance,
        param,
    ) orelse error.CreateWindowFailed;
}

pub fn destroy(hwnd: windows.HWND) void {
    _ = user32.DestroyWindow(hwnd);
}

pub fn show(hwnd: windows.HWND) void {
    _ = user32.ShowWindow(hwnd, user32.SW_SHOW);
    _ = user32.UpdateWindow(hwnd);
}

/// Request the window to close. Thread-safe: posts WM_CLOSE to the message
/// queue so teardown runs on the GUI thread via the window procedure.
pub fn postClose(hwnd: windows.HWND) void {
    _ = user32.PostMessageW(hwnd, user32.WM_CLOSE, 0, 0);
}

/// Apply a translucent acrylic backdrop when the config asks for translucency
/// (background-opacity < 1, or background-blur enabled). The renderer already
/// bakes background-opacity into the framebuffer alpha; this opts the window
/// into translucent DWM composition with an acrylic blur. Best-effort.
pub fn applyBackdrop(hwnd: windows.HWND, opacity: f64, blur_enabled: bool) void {
    dwmapi.setAcrylic(hwnd, opacity < 1.0 or blur_enabled);
}

/// The size of the window's client area in physical pixels.
pub fn clientSize(hwnd: windows.HWND) apprt.SurfaceSize {
    var rect: windows.RECT = undefined;
    if (user32.GetClientRect(hwnd, &rect) == windows.FALSE) {
        return .{ .width = 1, .height = 1 };
    }
    return .{
        .width = @intCast(@max(1, rect.right - rect.left)),
        .height = @intCast(@max(1, rect.bottom - rect.top)),
    };
}

/// The content scale (DPI / 96) for the window.
pub fn contentScale(hwnd: windows.HWND) apprt.ContentScale {
    const dpi = user32.GetDpiForWindow(hwnd);
    const scale: f32 = if (dpi == 0)
        1.0
    else
        @as(f32, @floatFromInt(dpi)) /
            @as(f32, @floatFromInt(user32.USER_DEFAULT_SCREEN_DPI));
    return .{ .x = scale, .y = scale };
}

/// Set the window title from a UTF-8 string.
pub fn setTitle(hwnd: windows.HWND, title: []const u8) void {
    var buf: [512]u16 = undefined;
    const len = std.unicode.utf8ToUtf16Le(&buf, title) catch return;
    if (len >= buf.len) return;
    buf[len] = 0;
    _ = user32.SetWindowTextW(hwnd, buf[0..len :0].ptr);
}
