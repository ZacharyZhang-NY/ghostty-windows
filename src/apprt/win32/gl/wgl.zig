//! WGL (Windows OpenGL) bindings: the base `opengl32.dll` entry points plus the
//! ARB/EXT extension function pointer types and tokens we need to create a
//! modern OpenGL >= 4.3 core context and control vsync. We hand-write this
//! subset (no WGL loader is vendored in `pkg/opengl`) following the style of
//! `src/os/windows.zig`.
const windows = @import("std").os.windows;

const BOOL = windows.BOOL;
const FLOAT = windows.FLOAT;
const UINT = windows.UINT;
const HDC = windows.HDC;
const HGLRC = windows.HGLRC;

/// A generic GL function pointer as returned by `wglGetProcAddress`.
pub const PROC = *align(@alignOf(fn () callconv(.c) void)) const anyopaque;

pub extern "opengl32" fn wglCreateContext(hdc: HDC) callconv(.winapi) ?HGLRC;
pub extern "opengl32" fn wglDeleteContext(hglrc: HGLRC) callconv(.winapi) BOOL;
pub extern "opengl32" fn wglMakeCurrent(
    hdc: ?HDC,
    hglrc: ?HGLRC,
) callconv(.winapi) BOOL;
pub extern "opengl32" fn wglGetProcAddress(
    name: [*:0]const u8,
) callconv(.winapi) ?PROC;
pub extern "opengl32" fn wglGetCurrentContext() callconv(.winapi) ?HGLRC;
pub extern "opengl32" fn wglGetCurrentDC() callconv(.winapi) ?HDC;

// ---------------------------------------------------------------------------
// WGL_ARB_create_context / WGL_ARB_create_context_profile
// ---------------------------------------------------------------------------

pub const CONTEXT_MAJOR_VERSION_ARB: c_int = 0x2091;
pub const CONTEXT_MINOR_VERSION_ARB: c_int = 0x2092;
pub const CONTEXT_FLAGS_ARB: c_int = 0x2094;
pub const CONTEXT_PROFILE_MASK_ARB: c_int = 0x9126;

pub const CONTEXT_DEBUG_BIT_ARB: c_int = 0x0001;
pub const CONTEXT_FORWARD_COMPATIBLE_BIT_ARB: c_int = 0x0002;
pub const CONTEXT_CORE_PROFILE_BIT_ARB: c_int = 0x0001;

pub const CreateContextAttribsARB = *const fn (
    hdc: HDC,
    share: ?HGLRC,
    attribs: [*:0]const c_int,
) callconv(.winapi) ?HGLRC;

// ---------------------------------------------------------------------------
// WGL_ARB_pixel_format
// ---------------------------------------------------------------------------

pub const DRAW_TO_WINDOW_ARB: c_int = 0x2001;
pub const ACCELERATION_ARB: c_int = 0x2003;
pub const SUPPORT_OPENGL_ARB: c_int = 0x2010;
pub const DOUBLE_BUFFER_ARB: c_int = 0x2011;
pub const PIXEL_TYPE_ARB: c_int = 0x2013;
pub const COLOR_BITS_ARB: c_int = 0x2014;
pub const ALPHA_BITS_ARB: c_int = 0x201B;
pub const DEPTH_BITS_ARB: c_int = 0x2022;
pub const STENCIL_BITS_ARB: c_int = 0x2023;
pub const FULL_ACCELERATION_ARB: c_int = 0x2027;
pub const TYPE_RGBA_ARB: c_int = 0x202B;
pub const FRAMEBUFFER_SRGB_CAPABLE_ARB: c_int = 0x20A9;

pub const ChoosePixelFormatARB = *const fn (
    hdc: HDC,
    int_attribs: [*:0]const c_int,
    float_attribs: ?[*:0]const FLOAT,
    max_formats: UINT,
    formats: [*]c_int,
    num_formats: *UINT,
) callconv(.winapi) BOOL;

// ---------------------------------------------------------------------------
// WGL_EXT_swap_control
// ---------------------------------------------------------------------------

pub const SwapIntervalEXT = *const fn (interval: c_int) callconv(.winapi) BOOL;
pub const GetSwapIntervalEXT = *const fn () callconv(.winapi) c_int;
