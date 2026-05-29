//! Win32 clipboard access (CF_UNICODETEXT only — Windows has a single system
//! clipboard, no selection/primary). Reads and writes are synchronous against
//! the global clipboard; callers own the returned UTF-8 buffer.
const std = @import("std");
const windows = std.os.windows;
const Allocator = std.mem.Allocator;

const BOOL = windows.BOOL;
const UINT = windows.UINT;
const HANDLE = windows.HANDLE;
const HWND = windows.HWND;
const LPVOID = windows.LPVOID;
const SIZE_T = usize;

const CF_UNICODETEXT: UINT = 13;
const GMEM_MOVEABLE: UINT = 0x0002;

pub const Error = error{
    OpenClipboardFailed,
    AllocFailed,
    SetClipboardFailed,
};

extern "user32" fn OpenClipboard(hwnd: ?HWND) callconv(.winapi) BOOL;
extern "user32" fn CloseClipboard() callconv(.winapi) BOOL;
extern "user32" fn EmptyClipboard() callconv(.winapi) BOOL;
extern "user32" fn GetClipboardData(format: UINT) callconv(.winapi) ?HANDLE;
extern "user32" fn SetClipboardData(
    format: UINT,
    mem: HANDLE,
) callconv(.winapi) ?HANDLE;
extern "user32" fn IsClipboardFormatAvailable(format: UINT) callconv(.winapi) BOOL;

extern "kernel32" fn GlobalAlloc(flags: UINT, bytes: SIZE_T) callconv(.winapi) ?HANDLE;
extern "kernel32" fn GlobalFree(mem: HANDLE) callconv(.winapi) ?HANDLE;
extern "kernel32" fn GlobalLock(mem: HANDLE) callconv(.winapi) ?LPVOID;
extern "kernel32" fn GlobalUnlock(mem: HANDLE) callconv(.winapi) BOOL;
extern "kernel32" fn GlobalSize(mem: HANDLE) callconv(.winapi) SIZE_T;

/// Read clipboard text as a freshly-allocated, null-terminated UTF-8 string.
/// Returns null when the clipboard holds no unicode text. Caller owns the slice.
pub fn readText(alloc: Allocator) Allocator.Error!?[:0]u8 {
    if (IsClipboardFormatAvailable(CF_UNICODETEXT) == windows.FALSE) return null;
    if (OpenClipboard(null) == windows.FALSE) return null;
    defer _ = CloseClipboard();

    const handle = GetClipboardData(CF_UNICODETEXT) orelse return null;
    const ptr = GlobalLock(handle) orelse return null;
    defer _ = GlobalUnlock(handle);

    // The data is a null-terminated UTF-16 string. GlobalSize is an upper
    // bound in bytes; scan for the terminator to find the real length.
    const max_units = GlobalSize(handle) / 2;
    const units: [*]const u16 = @ptrCast(@alignCast(ptr));
    var len: usize = 0;
    while (len < max_units and units[len] != 0) : (len += 1) {}

    // Malformed UTF-16 on the clipboard is treated as "no text" rather than an
    // error; only allocation failure propagates.
    return std.unicode.utf16LeToUtf8AllocZ(alloc, units[0..len]) catch |err| switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => null,
    };
}

/// Write UTF-8 text to the clipboard as CF_UNICODETEXT.
pub fn writeText(hwnd: ?HWND, text: []const u8) Error!void {
    if (OpenClipboard(hwnd) == windows.FALSE) return error.OpenClipboardFailed;
    defer _ = CloseClipboard();
    _ = EmptyClipboard();

    // Count UTF-16 code units (plus the null terminator) without allocating.
    var view = std.unicode.Utf8View.initUnchecked(text);
    var iter = view.iterator();
    var units: usize = 0;
    while (iter.nextCodepoint()) |cp| units += if (cp >= 0x10000) 2 else 1;

    const bytes: SIZE_T = (units + 1) * 2;
    const handle = GlobalAlloc(GMEM_MOVEABLE, bytes) orelse return error.AllocFailed;
    errdefer _ = GlobalFree(handle);

    const ptr = GlobalLock(handle) orelse return error.AllocFailed;
    const dst: [*]u16 = @ptrCast(@alignCast(ptr));
    const written = std.unicode.utf8ToUtf16Le(dst[0..units], text) catch {
        _ = GlobalUnlock(handle);
        return error.AllocFailed;
    };
    dst[written] = 0;
    _ = GlobalUnlock(handle);

    // On success the system owns the handle; do not free it.
    if (SetClipboardData(CF_UNICODETEXT, handle) == null) {
        return error.SetClipboardFailed;
    }
}
