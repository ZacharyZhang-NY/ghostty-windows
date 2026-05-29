//! The Win32 application runtime. It owns the process-wide configuration and
//! the GUI thread's message loop, hosts the core `App`, and creates `Surface`
//! windows. Cross-thread wakeups (from the renderer/IO threads via the core
//! mailbox) are delivered as a thread message that unblocks the message loop so
//! the core mailbox can be drained.
const App = @This();

const std = @import("std");
const builtin = @import("builtin");
const windows = std.os.windows;

const apprt = @import("../../apprt.zig");
const input = @import("../../input.zig");
const internal_os = @import("../../os/main.zig");
const configpkg = @import("../../config.zig");
const Config = configpkg.Config;
const CoreApp = @import("../../App.zig");

const Surface = @import("Surface.zig");
const Window = @import("Window.zig");
const window_proc = @import("window_proc.zig");
const user32 = @import("api/user32.zig");

const log = std.log.scoped(.win32_app);

/// The core application. Owned by the caller (main), lives at a stable address.
core_app: *CoreApp,

/// The process-wide configuration. Owned by this struct. The core reads this
/// directly (e.g. `rt_app.config.keybind`) so it must be a live field.
config: Config,

/// Module handle used as the window-class instance.
instance: windows.HINSTANCE,

/// The GUI thread id, captured in `run`, used to target wakeup messages.
thread_id: windows.DWORD,

/// Set false to break out of the message loop.
running: bool,

pub fn init(self: *App, core_app: *CoreApp, opts: struct {}) !void {
    _ = opts;

    // Per-monitor-v2 DPI awareness so we get crisp rendering and real pixel
    // sizes on high-DPI displays. Best-effort: ignore failure on older systems.
    _ = user32.SetProcessDpiAwarenessContext(
        user32.DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2,
    );

    const instance: windows.HINSTANCE = @ptrCast(user32.GetModuleHandleW(null) orelse
        return error.NoModuleHandle);

    try Window.register(instance, &window_proc.wndProc);

    const config = try Config.load(core_app.alloc);

    self.* = .{
        .core_app = core_app,
        .config = config,
        .instance = instance,
        .thread_id = 0,
        .running = false,
    };
}

pub fn terminate(self: *App) void {
    self.config.deinit();
}

/// The blocking GUI message loop. Creates the first window, then pumps Win32
/// messages, draining the core mailbox after each one.
pub fn run(self: *App) !void {
    self.thread_id = user32.GetCurrentThreadId();
    self.running = true;

    _ = try self.newSurface();

    var msg: user32.MSG = undefined;
    while (self.running) {
        const result = user32.GetMessageW(&msg, null, 0, 0);
        if (result <= 0) break; // 0 = WM_QUIT, -1 = error

        _ = user32.TranslateMessage(&msg);
        _ = user32.DispatchMessageW(&msg);

        self.core_app.tick(self) catch |err|
            log.warn("error in app tick err={}", .{err});

        if (self.core_app.surfaces.items.len == 0) self.running = false;
    }
}

/// Wake the message loop from any thread so the core mailbox is drained.
pub fn wakeup(self: *const App) void {
    if (self.thread_id == 0) return;
    _ = user32.PostThreadMessageW(self.thread_id, user32.WM_APP, 0, 0);
}

pub fn performAction(
    self: *App,
    target: apprt.Target,
    comptime action: apprt.Action.Key,
    value: apprt.Action.Value(action),
) !bool {
    switch (action) {
        .quit, .close_all_windows => {
            self.running = false;
            self.wakeup();
            return true;
        },

        .set_title => switch (target) {
            .app => return false,
            .surface => |core_surface| {
                try core_surface.rt_surface.setTitle(value.title);
                return true;
            },
        },

        else => return false,
    }
}

/// Keyboard-layout detection is macOS-only in core; Windows reports unknown.
pub fn keyboardLayout(self: *const App) input.KeyboardLayout {
    _ = self;
    return .unknown;
}

/// Create a new surface (window). The app owns the allocation.
fn newSurface(self: *App) !*Surface {
    const surface = try self.core_app.alloc.create(Surface);
    errdefer self.core_app.alloc.destroy(surface);
    try surface.init(self);
    return surface;
}

/// Close and free a surface. Safe to call from the window procedure.
pub fn closeSurface(self: *App, surface: *Surface) void {
    surface.deinit();
    self.core_app.alloc.destroy(surface);
}

/// IPC to an existing instance is not supported; always report "not handled".
pub fn performIpc(
    _: std.mem.Allocator,
    _: apprt.ipc.Target,
    comptime action: apprt.ipc.Action.Key,
    _: apprt.ipc.Action.Value(action),
) !bool {
    return false;
}
