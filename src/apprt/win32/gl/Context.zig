//! A modern OpenGL (>= 4.3 core) context for a Win32 window, created through
//! WGL. The renderer requires desktop GL 4.3, so we bootstrap the ARB context
//! creation entry points via a throwaway window (a pixel format can only be set
//! once per device context) and then build the real context on the live window.
//!
//! The context is owned by a `Surface` and is made current on the renderer
//! thread (see `renderer.OpenGL.threadEnter`); `glProcAddress` is the loader
//! handed to glad. Buffer swap and vsync are this layer's responsibility since
//! the OpenGL backend only blits to the default framebuffer.
const Context = @This();

const std = @import("std");
const windows = std.os.windows;
const wgl = @import("wgl.zig");
const gdi32 = @import("../api/gdi32.zig");
const user32 = @import("../api/user32.zig");

const log = std.log.scoped(.win32_gl);

pub const Error = error{
    GetDCFailed,
    PixelFormatFailed,
    ContextCreationFailed,
    MakeCurrentFailed,
    ExtensionLoadFailed,
};

/// A GL function pointer in the shape glad's loader expects.
pub const GlProc = *const fn () callconv(.c) void;

hwnd: windows.HWND,
hdc: windows.HDC,
hglrc: windows.HGLRC,

/// ARB entry points, loaded once per process via a bootstrap context.
var create_context_attribs: ?wgl.CreateContextAttribsARB = null;
var choose_pixel_format: ?wgl.ChoosePixelFormatARB = null;
var swap_interval: ?wgl.SwapIntervalEXT = null;
var ext_loaded: bool = false;

/// Lazily-loaded `opengl32.dll` handle for resolving GL 1.1 core entry points
/// that `wglGetProcAddress` does not return.
var opengl32: ?windows.HMODULE = null;

extern "kernel32" fn LoadLibraryA(name: [*:0]const u8) callconv(.winapi) ?windows.HMODULE;
extern "kernel32" fn GetProcAddress(
    module: windows.HMODULE,
    name: [*:0]const u8,
) callconv(.winapi) ?wgl.PROC;

/// Create a GL 4.3 core context for the given live window.
pub fn init(hwnd: windows.HWND, debug: bool) Error!Context {
    try loadExtensions();

    const hdc = user32.GetDC(hwnd) orelse return error.GetDCFailed;
    errdefer _ = user32.ReleaseDC(hwnd, hdc);

    try setPixelFormat(hdc);

    const attribs = [_:0]c_int{
        wgl.CONTEXT_MAJOR_VERSION_ARB, 4,
        wgl.CONTEXT_MINOR_VERSION_ARB, 3,
        wgl.CONTEXT_PROFILE_MASK_ARB,  wgl.CONTEXT_CORE_PROFILE_BIT_ARB,
        wgl.CONTEXT_FLAGS_ARB,         if (debug) wgl.CONTEXT_DEBUG_BIT_ARB else 0,
    };
    const create = create_context_attribs orelse return error.ExtensionLoadFailed;
    const hglrc = create(hdc, null, &attribs) orelse
        return error.ContextCreationFailed;

    return .{ .hwnd = hwnd, .hdc = hdc, .hglrc = hglrc };
}

pub fn deinit(self: *Context) void {
    if (wgl.wglGetCurrentContext() == self.hglrc) {
        _ = wgl.wglMakeCurrent(null, null);
    }
    _ = wgl.wglDeleteContext(self.hglrc);
    _ = user32.ReleaseDC(self.hwnd, self.hdc);
    self.* = undefined;
}

/// Make this context current on the calling thread.
pub fn makeCurrent(self: *const Context) Error!void {
    if (wgl.wglMakeCurrent(self.hdc, self.hglrc) == windows.FALSE) {
        return error.MakeCurrentFailed;
    }
}

/// Release the current context on the calling thread.
pub fn clearCurrent(self: *const Context) void {
    if (wgl.wglGetCurrentContext() == self.hglrc) {
        _ = wgl.wglMakeCurrent(null, null);
    }
}

/// Swap the front and back buffers, presenting the rendered frame.
pub fn swapBuffers(self: *const Context) void {
    _ = gdi32.SwapBuffers(self.hdc);
}

/// Set the swap interval (1 = vsync, 0 = off). No-op if the extension is
/// unavailable. The caller must have this context current.
pub fn setSwapInterval(interval: c_int) void {
    if (swap_interval) |f| _ = f(interval);
}

/// glad-compatible loader: resolve a GL entry point. `wglGetProcAddress` only
/// resolves extension functions, so we fall back to `opengl32.dll` for the
/// GL 1.1 core entry points. Requires a current context.
pub fn glProcAddress(name: [*:0]const u8) callconv(.c) ?GlProc {
    if (wgl.wglGetProcAddress(name)) |p| {
        // Some drivers return small sentinel values for unsupported names.
        switch (@intFromPtr(p)) {
            0, 1, 2, 3, ~@as(usize, 0) => {},
            else => return @ptrCast(p),
        }
    }

    const module = opengl32 orelse mod: {
        const m = LoadLibraryA("opengl32.dll");
        opengl32 = m;
        break :mod m;
    } orelse return null;

    return @ptrCast(GetProcAddress(module, name));
}

/// Choose and set a pixel format on the device context. Prefers
/// `wglChoosePixelFormatARB` for a hardware-accelerated, double-buffered,
/// sRGB-capable RGBA format and falls back to the legacy path.
fn setPixelFormat(hdc: windows.HDC) Error!void {
    var format: c_int = 0;

    if (choose_pixel_format) |choose| {
        const attribs = [_:0]c_int{
            wgl.DRAW_TO_WINDOW_ARB,           windows.TRUE,
            wgl.SUPPORT_OPENGL_ARB,           windows.TRUE,
            wgl.DOUBLE_BUFFER_ARB,            windows.TRUE,
            wgl.ACCELERATION_ARB,             wgl.FULL_ACCELERATION_ARB,
            wgl.PIXEL_TYPE_ARB,               wgl.TYPE_RGBA_ARB,
            wgl.COLOR_BITS_ARB,               24,
            wgl.ALPHA_BITS_ARB,               8,
            wgl.FRAMEBUFFER_SRGB_CAPABLE_ARB, windows.TRUE,
        };
        var count: windows.UINT = 0;
        if (choose(hdc, &attribs, null, 1, @ptrCast(&format), &count) != windows.FALSE and
            count > 0)
        {
            var pfd: gdi32.PIXELFORMATDESCRIPTOR = undefined;
            _ = gdi32.DescribePixelFormat(hdc, format, @sizeOf(gdi32.PIXELFORMATDESCRIPTOR), &pfd);
            if (gdi32.SetPixelFormat(hdc, format, &pfd) == windows.FALSE) {
                return error.PixelFormatFailed;
            }
            return;
        }
    }

    const pfd = legacyPixelFormat();
    format = gdi32.ChoosePixelFormat(hdc, &pfd);
    if (format == 0) return error.PixelFormatFailed;
    if (gdi32.SetPixelFormat(hdc, format, &pfd) == windows.FALSE) {
        return error.PixelFormatFailed;
    }
}

fn legacyPixelFormat() gdi32.PIXELFORMATDESCRIPTOR {
    var pfd = std.mem.zeroes(gdi32.PIXELFORMATDESCRIPTOR);
    pfd.nSize = @sizeOf(gdi32.PIXELFORMATDESCRIPTOR);
    pfd.nVersion = 1;
    pfd.dwFlags = gdi32.PFD_DRAW_TO_WINDOW |
        gdi32.PFD_SUPPORT_OPENGL |
        gdi32.PFD_DOUBLEBUFFER;
    pfd.iPixelType = gdi32.PFD_TYPE_RGBA;
    pfd.cColorBits = 24;
    pfd.cAlphaBits = 8;
    pfd.iLayerType = gdi32.PFD_MAIN_PLANE;
    return pfd;
}

/// Load the ARB context-creation entry points once per process by spinning up a
/// throwaway legacy context on a hidden bootstrap window.
fn loadExtensions() Error!void {
    if (ext_loaded) return;

    const instance = user32.GetModuleHandleW(null);
    const class_name = std.unicode.utf8ToUtf16LeStringLiteral("GhosttyWGLBootstrap");

    const wcx: user32.WNDCLASSEXW = .{
        .cbSize = @sizeOf(user32.WNDCLASSEXW),
        .style = user32.CS_OWNDC,
        .lpfnWndProc = &user32.DefWindowProcW,
        .cbClsExtra = 0,
        .cbWndExtra = 0,
        .hInstance = @ptrCast(instance),
        .hIcon = null,
        .hCursor = null,
        .hbrBackground = null,
        .lpszMenuName = null,
        .lpszClassName = class_name,
        .hIconSm = null,
    };
    _ = user32.RegisterClassExW(&wcx);
    defer _ = user32.UnregisterClassW(class_name, @ptrCast(instance));

    const hwnd = user32.CreateWindowExW(
        0,
        class_name,
        class_name,
        user32.WS_CLIPSIBLINGS | user32.WS_CLIPCHILDREN,
        0,
        0,
        1,
        1,
        null,
        null,
        @ptrCast(instance),
        null,
    ) orelse return error.ExtensionLoadFailed;
    defer _ = user32.DestroyWindow(hwnd);

    const hdc = user32.GetDC(hwnd) orelse return error.GetDCFailed;
    defer _ = user32.ReleaseDC(hwnd, hdc);

    const pfd = legacyPixelFormat();
    const format = gdi32.ChoosePixelFormat(hdc, &pfd);
    if (format == 0) return error.PixelFormatFailed;
    if (gdi32.SetPixelFormat(hdc, format, &pfd) == windows.FALSE) {
        return error.PixelFormatFailed;
    }

    const rc = wgl.wglCreateContext(hdc) orelse return error.ContextCreationFailed;
    defer _ = wgl.wglDeleteContext(rc);
    if (wgl.wglMakeCurrent(hdc, rc) == windows.FALSE) return error.MakeCurrentFailed;
    defer _ = wgl.wglMakeCurrent(null, null);

    create_context_attribs = @ptrCast(wgl.wglGetProcAddress("wglCreateContextAttribsARB"));
    choose_pixel_format = @ptrCast(wgl.wglGetProcAddress("wglChoosePixelFormatARB"));
    swap_interval = @ptrCast(wgl.wglGetProcAddress("wglSwapIntervalEXT"));

    if (create_context_attribs == null) return error.ExtensionLoadFailed;
    ext_loaded = true;
}
