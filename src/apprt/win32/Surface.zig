//! A single Win32 top-level window surface. It owns the OS window and its WGL
//! OpenGL context, embeds a `CoreSurface` (which spawns the renderer and IO
//! threads), and translates window-procedure events into core callbacks. It
//! also satisfies the `rt_surface` contract the core reads (size, scale, cursor
//! position, title, clipboard, environment).
const Surface = @This();

const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const windows = std.os.windows;

const apprt = @import("../../apprt.zig");
const input = @import("../../input.zig");
const internal_os = @import("../../os/main.zig");
const terminal = @import("../../terminal/main.zig");
const CoreSurface = @import("../../Surface.zig");

const App = @import("App.zig");
const Window = @import("Window.zig");
const Context = @import("gl/Context.zig");
const clipboard = @import("clipboard.zig");
const cursor = @import("cursor.zig");
const winput = @import("input.zig");

const log = std.log.scoped(.win32_surface);

const default_width: i32 = 800;
const default_height: i32 = 600;
const default_title = std.unicode.utf8ToUtf16LeStringLiteral("Ghostty");

/// The owning application runtime.
app: *App,

/// The core surface. Owns the renderer + IO threads.
core_surface: CoreSurface,

/// The OS window and its GL context.
hwnd: windows.HWND,
gl: Context,

/// Client-area size in physical pixels, updated on WM_SIZE.
size: apprt.SurfaceSize,

/// Lock-free copy of `size` for the renderer thread to set the GL viewport.
/// Packed as (width << 32) | height.
size_atomic: std.atomic.Value(u64),

/// DPI scale (DPI / 96), updated on WM_DPICHANGED.
content_scale: apprt.ContentScale,

/// Last known cursor position in physical pixels.
cursor_pos: apprt.CursorPos,

/// Window title, owned, UTF-8, null-terminated. Updated via the set_title action.
title: ?[:0]u8,

/// Whether we've armed WM_MOUSELEAVE tracking for the current hover.
mouse_tracking: bool,

/// The cursor shape the terminal wants over the client area, and whether the
/// cursor is currently visible (hidden while typing).
mouse_shape: terminal.MouseShape,
mouse_visible: bool,

/// Initialize the surface: create the window + GL context, then wire the core
/// surface (which starts the renderer and IO threads). Must run on the app
/// thread. The GL context is created here but made current on the render thread.
pub fn init(self: *Surface, app: *App) !void {
    const alloc = app.core_app.alloc;

    self.* = .{
        .app = app,
        .core_surface = undefined,
        .hwnd = undefined,
        .gl = undefined,
        .size = .{ .width = default_width, .height = default_height },
        .size_atomic = .init((@as(u64, default_width) << 32) | default_height),
        .content_scale = .{ .x = 1, .y = 1 },
        .cursor_pos = .{ .x = 0, .y = 0 },
        .title = null,
        .mouse_tracking = false,
        .mouse_shape = .text,
        .mouse_visible = true,
    };

    self.hwnd = try Window.create(
        app.instance,
        default_title,
        default_width,
        default_height,
        self,
    );
    errdefer Window.destroy(self.hwnd);

    self.size = Window.clientSize(self.hwnd);
    self.content_scale = Window.contentScale(self.hwnd);
    self.storeSize();

    self.gl = try Context.init(self.hwnd, builtin.mode == .Debug);
    errdefer self.gl.deinit();

    try self.core_surface.init(
        alloc,
        &app.config,
        app.core_app,
        app,
        self,
    );
    errdefer self.core_surface.deinit();

    try app.core_app.addSurface(self);
    errdefer app.core_app.deleteSurface(self);

    Window.show(self.hwnd);
}

pub fn deinit(self: *Surface) void {
    // Remove from the app's surface list first, then tear down the renderer +
    // IO threads and free GL resources (the core re-enters our GL context on
    // this thread to do so).
    self.app.core_app.deleteSurface(self);
    self.core_surface.deinit();
    self.gl.deinit();
    Window.destroy(self.hwnd);
    if (self.title) |t| self.app.core_app.alloc.free(t);
}

fn storeSize(self: *Surface) void {
    self.size_atomic.store(
        (@as(u64, self.size.width) << 32) | self.size.height,
        .monotonic,
    );
}

// --- rt_surface contract (called by the core) ---------------------------------

pub fn core(self: *Surface) *CoreSurface {
    return &self.core_surface;
}

pub fn rtApp(self: *const Surface) *App {
    return self.app;
}

/// Called by the core when the surface should close (e.g. the child process
/// exited). We request the window to close; teardown happens on the GUI thread.
pub fn close(self: *Surface, process_alive: bool) void {
    _ = process_alive;
    Window.postClose(self.hwnd);
}

pub fn getContentScale(self: *const Surface) !apprt.ContentScale {
    return self.content_scale;
}

pub fn getSize(self: *const Surface) !apprt.SurfaceSize {
    return self.size;
}

pub fn getCursorPos(self: *const Surface) !apprt.CursorPos {
    return self.cursor_pos;
}

pub fn getTitle(self: *Surface) ?[:0]const u8 {
    return self.title;
}

pub fn setTitle(self: *Surface, slice: []const u8) !void {
    const alloc = self.app.core_app.alloc;
    if (self.title) |t| alloc.free(t);
    self.title = try alloc.dupeZ(u8, slice);
    Window.setTitle(self.hwnd, slice);
}

pub fn supportsClipboard(self: *const Surface, clipboard_type: apprt.Clipboard) bool {
    _ = self;
    return clipboard_type == .standard;
}

pub fn clipboardRequest(
    self: *Surface,
    clipboard_type: apprt.Clipboard,
    state: apprt.ClipboardRequest,
) !bool {
    if (clipboard_type != .standard) return false;

    const alloc = self.app.core_app.alloc;
    const text = (try clipboard.readText(alloc)) orelse return true;
    defer alloc.free(text);

    self.core_surface.completeClipboardRequest(state, text, false) catch |err| switch (err) {
        error.UnsafePaste, error.UnauthorizedPaste => {
            log.warn("clipboard paste rejected as unsafe; not pasting", .{});
        },
        else => return err,
    };
    return true;
}

pub fn setClipboard(
    self: *const Surface,
    clipboard_type: apprt.Clipboard,
    contents: []const apprt.ClipboardContent,
    confirm: bool,
) !void {
    _ = confirm;
    if (clipboard_type != .standard) return;
    for (contents) |content| {
        if (std.mem.eql(u8, content.mime, "text/plain")) {
            try clipboard.writeText(self.hwnd, content.data);
            return;
        }
    }
    if (contents.len > 0) try clipboard.writeText(self.hwnd, contents[0].data);
}

pub fn defaultTermioEnv(self: *const Surface) !std.process.EnvMap {
    return internal_os.getEnvMap(self.app.core_app.alloc);
}

/// The Win32 cursor to show over the client area, or null to hide it.
pub fn currentCursor(self: *const Surface) ?windows.HCURSOR {
    if (!self.mouse_visible) return null;
    return cursor.load(self.mouse_shape);
}

// --- window-procedure event handlers ------------------------------------------

pub fn onResize(self: *Surface, width: u32, height: u32) void {
    self.size = .{ .width = @max(1, width), .height = @max(1, height) };
    self.storeSize();
    self.core_surface.sizeCallback(self.size) catch |err|
        log.warn("error in size callback err={}", .{err});
}

pub fn onDpiChanged(self: *Surface, dpi: u32) void {
    const scale: f32 = @as(f32, @floatFromInt(dpi)) / 96.0;
    self.content_scale = .{ .x = scale, .y = scale };
    self.core_surface.contentScaleCallback(self.content_scale) catch |err|
        log.warn("error in content scale callback err={}", .{err});
}

pub fn onFocus(self: *Surface, focused: bool) void {
    self.core_surface.focusCallback(focused) catch |err|
        log.warn("error in focus callback err={}", .{err});
}

pub fn onCursorPos(self: *Surface, x: i32, y: i32) void {
    self.cursor_pos = .{ .x = @floatFromInt(x), .y = @floatFromInt(y) };
    self.core_surface.cursorPosCallback(self.cursor_pos, winput.currentMods()) catch |err|
        log.warn("error in cursor pos callback err={}", .{err});
}

pub fn onMouseLeave(self: *Surface) void {
    self.mouse_tracking = false;
    self.core_surface.cursorPosCallback(.{ .x = -1, .y = -1 }, null) catch {};
}

pub fn onMouseButton(
    self: *Surface,
    state: input.MouseButtonState,
    button: input.MouseButton,
) void {
    _ = self.core_surface.mouseButtonCallback(
        state,
        button,
        winput.currentMods(),
    ) catch |err| log.warn("error in mouse button callback err={}", .{err});
}

pub fn onScroll(self: *Surface, xoff: f64, yoff: f64) void {
    self.core_surface.scrollCallback(xoff, yoff, .{}) catch |err|
        log.warn("error in scroll callback err={}", .{err});
}

/// Deliver a key event to the core. `utf8` is the text the key produced (from
/// the matching WM_CHAR), empty for control/special keys. Matching Ghostty's
/// model, this is the single input path: the key encoder emits the text for us,
/// so there is no separate paste-style text callback for typing.
///
/// Returns true if the surface was closed by this key event (pointers are then
/// invalid and the caller must stop touching it).
///
/// Note: there is intentionally no paint handler. The renderer owns the GL
/// context on its own thread and draws continuously; the window procedure only
/// validates the client area on WM_PAINT. Drawing here (on the app thread)
/// would use GL without a current context and corrupt rendering.
pub fn onKey(
    self: *Surface,
    action: input.Action,
    vk: u32,
    scancode: u32,
    utf8: []const u8,
) bool {
    const ev: input.KeyEvent = .{
        .action = action,
        .key = winput.keyFromScancode(scancode),
        .mods = winput.currentMods(),
        .utf8 = utf8,
        .unshifted_codepoint = unshiftedCodepoint(vk),
    };
    const effect = self.core_surface.keyCallback(ev) catch |err| {
        log.warn("error in key callback err={}", .{err});
        return false;
    };
    return effect == .closed;
}

fn unshiftedCodepoint(vk: u32) u21 {
    const ch = winput.user32_MapVirtualKeyToChar(vk);
    if (ch == 0 or ch >= 0x80) return @intCast(ch & 0x7F);
    // ASCII letters report uppercase; the unshifted form is lowercase.
    if (ch >= 'A' and ch <= 'Z') return @intCast(ch + 32);
    return @intCast(ch);
}
