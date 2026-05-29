//! Translation between Win32 keyboard/mouse input and Ghostty's
//! platform-agnostic `input` types. Physical keys come from the shared
//! `keycodes` table (the `.windows` column holds Win32 virtual-key codes);
//! modifier state is read live via `GetKeyState`.
const std = @import("std");
const input = @import("../../input.zig");
const user32 = @import("api/user32.zig");

/// Virtual-key codes for modifiers and the lock keys.
const VK_SHIFT: c_int = 0x10;
const VK_CONTROL: c_int = 0x11;
const VK_MENU: c_int = 0x12;
const VK_CAPITAL: c_int = 0x14;
const VK_LWIN: c_int = 0x5B;
const VK_RWIN: c_int = 0x5C;
const VK_NUMLOCK: c_int = 0x90;

/// Map a Win32 scan code to a layout-independent `input.Key`. Ghostty's keycode
/// table stores Set 1 scan codes in its Windows column (extended keys use the
/// 0xE000 prefix), not virtual-key codes, so physical-key matching must be done
/// by scan code.
pub fn keyFromScancode(scancode: u32) input.Key {
    for (input.keycodes.entries) |entry| {
        if (entry.native == scancode) return entry.key;
    }
    return .unidentified;
}

/// The unshifted character a virtual-key maps to in the active layout, or 0.
pub fn user32_MapVirtualKeyToChar(vk: u32) u32 {
    return user32.MapVirtualKeyW(vk, user32.MAPVK_VK_TO_CHAR);
}

inline fn down(vk: c_int) bool {
    return (@as(u16, @bitCast(user32.GetKeyState(vk))) & 0x8000) != 0;
}

inline fn toggled(vk: c_int) bool {
    return (@as(u16, @bitCast(user32.GetKeyState(vk))) & 0x0001) != 0;
}

/// The current modifier state, read from the keyboard at call time.
pub fn currentMods() input.Mods {
    return .{
        .shift = down(VK_SHIFT),
        .ctrl = down(VK_CONTROL),
        .alt = down(VK_MENU),
        .super = down(VK_LWIN) or down(VK_RWIN),
        .caps_lock = toggled(VK_CAPITAL),
        .num_lock = toggled(VK_NUMLOCK),
    };
}

/// Accumulates UTF-16 code units delivered by WM_CHAR into UTF-8, joining
/// surrogate pairs. A single high surrogate is held until its low surrogate
/// arrives in the following message.
pub const CharDecoder = struct {
    high: ?u16 = null,

    /// Feed one UTF-16 code unit. Returns the decoded UTF-8 bytes in `buf`
    /// when a full scalar is available, or null while awaiting a low surrogate
    /// or on an invalid sequence.
    pub fn next(self: *CharDecoder, unit: u16, buf: *[4]u8) ?[]const u8 {
        const cp: u21 = cp: {
            if (self.high) |hi| {
                self.high = null;
                if (unit >= 0xDC00 and unit <= 0xDFFF) {
                    break :cp 0x10000 +
                        (@as(u21, hi - 0xD800) << 10) +
                        (unit - 0xDC00);
                }
                // Lone high surrogate; fall through to treat `unit` fresh.
            }
            if (unit >= 0xD800 and unit <= 0xDBFF) {
                self.high = unit;
                return null;
            }
            if (unit >= 0xDC00 and unit <= 0xDFFF) return null;
            break :cp unit;
        };

        const len = std.unicode.utf8Encode(cp, buf) catch return null;
        return buf[0..len];
    }
};
