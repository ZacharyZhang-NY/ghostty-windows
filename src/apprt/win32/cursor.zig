//! Maps Ghostty's platform-agnostic mouse cursor shapes (W3C cursor styles) to
//! Win32 standard cursors. System cursors loaded via LoadCursorW with a null
//! instance are shared and must not be destroyed, so no caching is needed.
const std = @import("std");
const windows = std.os.windows;
const terminal = @import("../../terminal/main.zig");
const user32 = @import("api/user32.zig");

// Standard cursor resource identifiers (IDC_*), encoded via MAKEINTRESOURCE.
const IDC_ARROW: u16 = 32512;
const IDC_IBEAM: u16 = 32513;
const IDC_WAIT: u16 = 32514;
const IDC_CROSS: u16 = 32515;
const IDC_SIZENWSE: u16 = 32642;
const IDC_SIZENESW: u16 = 32643;
const IDC_SIZEWE: u16 = 32644;
const IDC_SIZENS: u16 = 32645;
const IDC_SIZEALL: u16 = 32646;
const IDC_NO: u16 = 32648;
const IDC_HAND: u16 = 32649;
const IDC_APPSTARTING: u16 = 32650;
const IDC_HELP: u16 = 32651;

// MAKEINTRESOURCE: a standard cursor id is an ordinal in the low word, not a
// real pointer, so it has no alignment requirement. Use an align(1) pointer so
// @ptrFromInt does not assert 2-byte alignment for odd ids (e.g. IDC_IBEAM).
inline fn idc(id: u16) [*:0]align(1) const u16 {
    return @ptrFromInt(id);
}

/// Load the Win32 cursor that best represents the given shape.
pub fn load(shape: terminal.MouseShape) ?windows.HCURSOR {
    const id: u16 = switch (shape) {
        .text, .vertical_text => IDC_IBEAM,
        .pointer, .grab, .grabbing => IDC_HAND,
        .wait => IDC_WAIT,
        .progress => IDC_APPSTARTING,
        .help => IDC_HELP,
        .crosshair, .cell => IDC_CROSS,
        .not_allowed, .no_drop => IDC_NO,
        .move, .all_scroll => IDC_SIZEALL,
        .col_resize, .e_resize, .w_resize, .ew_resize => IDC_SIZEWE,
        .row_resize, .n_resize, .s_resize, .ns_resize => IDC_SIZENS,
        .ne_resize, .sw_resize, .nesw_resize => IDC_SIZENESW,
        .nw_resize, .se_resize, .nwse_resize => IDC_SIZENWSE,
        else => IDC_ARROW,
    };
    return user32.LoadCursorW(null, idc(id));
}
