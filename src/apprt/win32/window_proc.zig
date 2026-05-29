//! The window procedure: translates Win32 window messages into `Surface`
//! handler calls. The owning `Surface` pointer is stashed in the window's
//! user data on WM_NCCREATE and recovered for every subsequent message.
const std = @import("std");
const windows = std.os.windows;
const user32 = @import("api/user32.zig");
const input = @import("../../input.zig");
const Surface = @import("Surface.zig");

const UINT = windows.UINT;
const WPARAM = windows.WPARAM;
const LPARAM = windows.LPARAM;
const LRESULT = windows.LRESULT;
const HWND = windows.HWND;

inline fn loword(value: usize) u16 {
    return @truncate(value);
}
inline fn hiword(value: usize) u16 {
    return @truncate(value >> 16);
}
inline fn signedLo(value: usize) i32 {
    return @as(i16, @bitCast(loword(value)));
}
inline fn signedHi(value: usize) i32 {
    return @as(i16, @bitCast(hiword(value)));
}

fn surfaceFrom(hwnd: HWND) ?*Surface {
    const ptr = user32.GetWindowLongPtrW(hwnd, user32.GWLP_USERDATA);
    if (ptr == 0) return null;
    return @ptrFromInt(@as(usize, @bitCast(ptr)));
}

pub fn wndProc(
    hwnd: HWND,
    msg: UINT,
    wparam: WPARAM,
    lparam: LPARAM,
) callconv(.winapi) LRESULT {
    if (msg == user32.WM_NCCREATE) {
        const cs: *user32.CREATESTRUCTW = @ptrFromInt(@as(usize, @bitCast(lparam)));
        if (cs.lpCreateParams) |param| {
            _ = user32.SetWindowLongPtrW(
                hwnd,
                user32.GWLP_USERDATA,
                @bitCast(@intFromPtr(param)),
            );
        }
        return user32.DefWindowProcW(hwnd, msg, wparam, lparam);
    }

    const surface = surfaceFrom(hwnd) orelse
        return user32.DefWindowProcW(hwnd, msg, wparam, lparam);

    const wp: usize = @bitCast(wparam);
    const lp: usize = @bitCast(lparam);

    switch (msg) {
        user32.WM_SIZE => {
            surface.onResize(loword(lp), hiword(lp));
            return 0;
        },

        user32.WM_PAINT => {
            // The render thread draws continuously on its own GL context; just
            // mark the client area valid so Windows stops re-posting WM_PAINT.
            _ = user32.ValidateRect(hwnd, null);
            return 0;
        },

        // We render the whole client area with GL; suppress GDI erase.
        user32.WM_ERASEBKGND => return 1,

        user32.WM_SETFOCUS => {
            surface.onFocus(true);
            return 0;
        },
        user32.WM_KILLFOCUS => {
            surface.onFocus(false);
            return 0;
        },

        user32.WM_MOUSEMOVE => {
            if (!surface.mouse_tracking) {
                var tme: user32.TRACKMOUSEEVENT = .{
                    .cbSize = @sizeOf(user32.TRACKMOUSEEVENT),
                    .dwFlags = user32.TME_LEAVE,
                    .hwndTrack = hwnd,
                    .dwHoverTime = 0,
                };
                _ = user32.TrackMouseEvent(&tme);
                surface.mouse_tracking = true;
            }
            surface.onCursorPos(signedLo(lp), signedHi(lp));
            return 0;
        },
        user32.WM_MOUSELEAVE => {
            surface.onMouseLeave();
            return 0;
        },

        user32.WM_LBUTTONDOWN => return mouseButton(surface, hwnd, .press, .left),
        user32.WM_LBUTTONUP => return mouseButton(surface, hwnd, .release, .left),
        user32.WM_RBUTTONDOWN => return mouseButton(surface, hwnd, .press, .right),
        user32.WM_RBUTTONUP => return mouseButton(surface, hwnd, .release, .right),
        user32.WM_MBUTTONDOWN => return mouseButton(surface, hwnd, .press, .middle),
        user32.WM_MBUTTONUP => return mouseButton(surface, hwnd, .release, .middle),
        user32.WM_XBUTTONDOWN => return mouseButton(
            surface,
            hwnd,
            .press,
            if (hiword(wp) == user32.XBUTTON1) .four else .five,
        ),
        user32.WM_XBUTTONUP => return mouseButton(
            surface,
            hwnd,
            .release,
            if (hiword(wp) == user32.XBUTTON1) .four else .five,
        ),

        user32.WM_MOUSEWHEEL => {
            const delta: f64 = @as(f64, @floatFromInt(signedHi(wp))) / 120.0;
            surface.onScroll(0, delta);
            return 0;
        },
        user32.WM_MOUSEHWHEEL => {
            const delta: f64 = @as(f64, @floatFromInt(signedHi(wp))) / 120.0;
            surface.onScroll(delta, 0);
            return 0;
        },

        user32.WM_KEYDOWN => {
            const action: input.Action = if ((lp & 0x40000000) != 0) .repeat else .press;
            if (surface.onKey(action, @intCast(wp))) return 0;
            return 0;
        },
        user32.WM_KEYUP => {
            _ = surface.onKey(.release, @intCast(wp));
            return 0;
        },
        user32.WM_CHAR => {
            surface.onChar(@truncate(wp));
            return 0;
        },

        // System keys (Alt combos): forward to the core, but also let the
        // default handler run so Alt+F4 and system accelerators keep working.
        user32.WM_SYSKEYDOWN => {
            const action: input.Action = if ((lp & 0x40000000) != 0) .repeat else .press;
            _ = surface.onKey(action, @intCast(wp));
            return user32.DefWindowProcW(hwnd, msg, wparam, lparam);
        },
        user32.WM_SYSKEYUP => {
            _ = surface.onKey(.release, @intCast(wp));
            return user32.DefWindowProcW(hwnd, msg, wparam, lparam);
        },

        user32.WM_DPICHANGED => {
            surface.onDpiChanged(loword(wp));
            const suggested: *const windows.RECT = @ptrFromInt(@as(usize, @bitCast(lparam)));
            _ = user32.SetWindowPos(
                hwnd,
                null,
                suggested.left,
                suggested.top,
                suggested.right - suggested.left,
                suggested.bottom - suggested.top,
                user32.SWP_NOZORDER | user32.SWP_NOACTIVATE,
            );
            return 0;
        },

        user32.WM_CLOSE => {
            surface.app.closeSurface(surface);
            return 0;
        },

        else => return user32.DefWindowProcW(hwnd, msg, wparam, lparam),
    }
}

fn mouseButton(
    surface: *Surface,
    hwnd: HWND,
    state: input.MouseButtonState,
    button: input.MouseButton,
) LRESULT {
    switch (state) {
        .press => _ = user32.SetCapture(hwnd),
        .release => _ = user32.ReleaseCapture(),
    }
    surface.onMouseButton(state, button);
    return 0;
}
