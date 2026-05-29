//! Minimal GDI32 bindings required by the Win32 app runtime: pixel format
//! selection and buffer swapping for an OpenGL drawable. We hand-write the
//! subset we use to match the style of `src/os/windows.zig` and to keep both
//! the GNU and MSVC ABIs building without a system SDK header dependency.
const windows = @import("std").os.windows;

const BOOL = windows.BOOL;
const BYTE = windows.BYTE;
const DWORD = windows.DWORD;
const WORD = windows.WORD;
const UINT = windows.UINT;
const HDC = windows.HDC;

/// PIXELFORMATDESCRIPTOR. Field order and types mirror the Win32 definition
/// exactly so the `extern struct` C layout matches (40 bytes).
pub const PIXELFORMATDESCRIPTOR = extern struct {
    nSize: WORD,
    nVersion: WORD,
    dwFlags: DWORD,
    iPixelType: BYTE,
    cColorBits: BYTE,
    cRedBits: BYTE,
    cRedShift: BYTE,
    cGreenBits: BYTE,
    cGreenShift: BYTE,
    cBlueBits: BYTE,
    cBlueShift: BYTE,
    cAlphaBits: BYTE,
    cAlphaShift: BYTE,
    cAccumBits: BYTE,
    cAccumRedBits: BYTE,
    cAccumGreenBits: BYTE,
    cAccumBlueBits: BYTE,
    cAccumAlphaBits: BYTE,
    cDepthBits: BYTE,
    cStencilBits: BYTE,
    cAuxBuffers: BYTE,
    iLayerType: BYTE,
    bReserved: BYTE,
    dwLayerMask: DWORD,
    dwVisibleMask: DWORD,
    dwDamageMask: DWORD,
};

/// dwFlags bits.
pub const PFD_DOUBLEBUFFER: DWORD = 0x00000001;
pub const PFD_DRAW_TO_WINDOW: DWORD = 0x00000004;
pub const PFD_SUPPORT_OPENGL: DWORD = 0x00000020;

/// iPixelType values.
pub const PFD_TYPE_RGBA: BYTE = 0;

/// iLayerType values.
pub const PFD_MAIN_PLANE: BYTE = 0;

pub extern "gdi32" fn ChoosePixelFormat(
    hdc: HDC,
    ppfd: *const PIXELFORMATDESCRIPTOR,
) callconv(.winapi) c_int;

pub extern "gdi32" fn SetPixelFormat(
    hdc: HDC,
    format: c_int,
    ppfd: *const PIXELFORMATDESCRIPTOR,
) callconv(.winapi) BOOL;

pub extern "gdi32" fn DescribePixelFormat(
    hdc: HDC,
    format: c_int,
    bytes: UINT,
    ppfd: ?*PIXELFORMATDESCRIPTOR,
) callconv(.winapi) c_int;

pub extern "gdi32" fn SwapBuffers(hdc: HDC) callconv(.winapi) BOOL;
