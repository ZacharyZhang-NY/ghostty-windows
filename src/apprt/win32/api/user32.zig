//! Minimal USER32 (and a couple of KERNEL32) bindings required by the Win32 app
//! runtime: window class registration, window lifecycle, the message loop,
//! device-context acquisition, DPI awareness and the window/input message
//! tokens. Hand-written to match `src/os/windows.zig` and to build on both the
//! GNU and MSVC ABIs without a system SDK header dependency.
const windows = @import("std").os.windows;

const BOOL = windows.BOOL;
const DWORD = windows.DWORD;
const UINT = windows.UINT;
const LONG = windows.LONG;
const LONG_PTR = windows.LONG_PTR;
const WPARAM = windows.WPARAM;
const LPARAM = windows.LPARAM;
const LRESULT = windows.LRESULT;
const HWND = windows.HWND;
const HDC = windows.HDC;
const HINSTANCE = windows.HINSTANCE;
const HMODULE = windows.HMODULE;
const HMENU = windows.HMENU;
const HICON = windows.HICON;
const HCURSOR = windows.HCURSOR;
const HBRUSH = windows.HBRUSH;
const ATOM = windows.ATOM;
const LPCWSTR = windows.LPCWSTR;
const RECT = windows.RECT;
const POINT = windows.POINT;

pub const WNDPROC = *const fn (
    hwnd: HWND,
    msg: UINT,
    wparam: WPARAM,
    lparam: LPARAM,
) callconv(.winapi) LRESULT;

pub const WNDCLASSEXW = extern struct {
    cbSize: UINT,
    style: UINT,
    lpfnWndProc: WNDPROC,
    cbClsExtra: c_int,
    cbWndExtra: c_int,
    hInstance: HINSTANCE,
    hIcon: ?HICON,
    hCursor: ?HCURSOR,
    hbrBackground: ?HBRUSH,
    lpszMenuName: ?LPCWSTR,
    lpszClassName: LPCWSTR,
    hIconSm: ?HICON,
};

pub const MSG = extern struct {
    hwnd: ?HWND,
    message: UINT,
    wParam: WPARAM,
    lParam: LPARAM,
    time: DWORD,
    pt: POINT,
};

pub const CREATESTRUCTW = extern struct {
    lpCreateParams: ?*anyopaque,
    hInstance: ?HINSTANCE,
    hMenu: ?HMENU,
    hwndParent: ?HWND,
    cy: c_int,
    cx: c_int,
    y: c_int,
    x: c_int,
    style: LONG,
    lpszName: ?LPCWSTR,
    lpszClass: ?LPCWSTR,
    dwExStyle: DWORD,
};

pub const TRACKMOUSEEVENT = extern struct {
    cbSize: DWORD,
    dwFlags: DWORD,
    hwndTrack: ?HWND,
    dwHoverTime: DWORD,
};

/// Opaque handle used by the per-monitor DPI awareness APIs.
pub const DPI_AWARENESS_CONTEXT = *opaque {};
pub const DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2: DPI_AWARENESS_CONTEXT =
    @ptrFromInt(@as(usize, @bitCast(@as(isize, -4))));
pub const USER_DEFAULT_SCREEN_DPI: u32 = 96;

// WM_SETCURSOR hit-test code (low word of lParam) for the client area.
pub const HTCLIENT: u16 = 1;

// Window class styles.
pub const CS_VREDRAW: UINT = 0x0001;
pub const CS_HREDRAW: UINT = 0x0002;
pub const CS_OWNDC: UINT = 0x0020;

// Window styles.
pub const WS_OVERLAPPEDWINDOW: DWORD = 0x00CF0000;
pub const WS_CLIPSIBLINGS: DWORD = 0x04000000;
pub const WS_CLIPCHILDREN: DWORD = 0x02000000;
pub const WS_VISIBLE: DWORD = 0x10000000;

pub const CW_USEDEFAULT: c_int = @bitCast(@as(u32, 0x80000000));

// ShowWindow commands.
pub const SW_HIDE: c_int = 0;
pub const SW_SHOW: c_int = 5;
pub const SW_SHOWDEFAULT: c_int = 10;

// GetWindowLongPtr / SetWindowLongPtr indices.
pub const GWLP_USERDATA: c_int = -21;

// Standard cursor (IDC_ARROW) encoded via MAKEINTRESOURCE.
pub const IDC_ARROW: LPCWSTR = @ptrFromInt(32512);

// PeekMessage removal flags.
pub const PM_NOREMOVE: UINT = 0x0000;
pub const PM_REMOVE: UINT = 0x0001;

// TrackMouseEvent flags.
pub const TME_LEAVE: DWORD = 0x00000002;

// Window and input messages we dispatch on.
pub const WM_CREATE: UINT = 0x0001;
pub const WM_DESTROY: UINT = 0x0002;
pub const WM_SIZE: UINT = 0x0005;
pub const WM_SETFOCUS: UINT = 0x0007;
pub const WM_KILLFOCUS: UINT = 0x0008;
pub const WM_PAINT: UINT = 0x000F;
pub const WM_CLOSE: UINT = 0x0010;
pub const WM_QUIT: UINT = 0x0012;
pub const WM_ERASEBKGND: UINT = 0x0014;
pub const WM_SETCURSOR: UINT = 0x0020;
pub const WM_NCCREATE: UINT = 0x0081;
pub const WM_KEYDOWN: UINT = 0x0100;
pub const WM_KEYUP: UINT = 0x0101;
pub const WM_CHAR: UINT = 0x0102;
pub const WM_SYSKEYDOWN: UINT = 0x0104;
pub const WM_SYSKEYUP: UINT = 0x0105;
pub const WM_SYSCHAR: UINT = 0x0106;
pub const WM_MOUSEMOVE: UINT = 0x0200;
pub const WM_LBUTTONDOWN: UINT = 0x0201;
pub const WM_LBUTTONUP: UINT = 0x0202;
pub const WM_RBUTTONDOWN: UINT = 0x0204;
pub const WM_RBUTTONUP: UINT = 0x0205;
pub const WM_MBUTTONDOWN: UINT = 0x0207;
pub const WM_MBUTTONUP: UINT = 0x0208;
pub const WM_MOUSEWHEEL: UINT = 0x020A;
pub const WM_XBUTTONDOWN: UINT = 0x020B;
pub const WM_XBUTTONUP: UINT = 0x020C;
pub const WM_MOUSEHWHEEL: UINT = 0x020E;
pub const WM_MOUSELEAVE: UINT = 0x02A3;
pub const WM_DPICHANGED: UINT = 0x02E0;
pub const WM_APP: UINT = 0x8000;

// XBUTTON identifiers in the high word of WPARAM for WM_XBUTTON* messages.
pub const XBUTTON1: u16 = 0x0001;
pub const XBUTTON2: u16 = 0x0002;

pub extern "kernel32" fn GetModuleHandleW(
    name: ?LPCWSTR,
) callconv(.winapi) ?HMODULE;
pub extern "kernel32" fn GetCurrentThreadId() callconv(.winapi) DWORD;

pub extern "user32" fn PostThreadMessageW(
    thread_id: DWORD,
    msg: UINT,
    wparam: WPARAM,
    lparam: LPARAM,
) callconv(.winapi) BOOL;

pub extern "user32" fn RegisterClassExW(
    wcx: *const WNDCLASSEXW,
) callconv(.winapi) ATOM;
pub extern "user32" fn UnregisterClassW(
    class: LPCWSTR,
    instance: ?HINSTANCE,
) callconv(.winapi) BOOL;
pub extern "user32" fn LoadCursorW(
    instance: ?HINSTANCE,
    // align(1): the name may be a MAKEINTRESOURCE ordinal (odd-valued), not a
    // real 2-byte-aligned string pointer.
    name: [*:0]align(1) const u16,
) callconv(.winapi) ?HCURSOR;
pub extern "user32" fn SetCursor(cursor: ?HCURSOR) callconv(.winapi) ?HCURSOR;

pub extern "user32" fn CreateWindowExW(
    ex_style: DWORD,
    class_name: ?LPCWSTR,
    window_name: ?LPCWSTR,
    style: DWORD,
    x: c_int,
    y: c_int,
    width: c_int,
    height: c_int,
    parent: ?HWND,
    menu: ?HMENU,
    instance: ?HINSTANCE,
    param: ?*anyopaque,
) callconv(.winapi) ?HWND;
pub extern "user32" fn DestroyWindow(hwnd: HWND) callconv(.winapi) BOOL;
pub extern "user32" fn ShowWindow(hwnd: HWND, cmd: c_int) callconv(.winapi) BOOL;
pub extern "user32" fn UpdateWindow(hwnd: HWND) callconv(.winapi) BOOL;
pub extern "user32" fn GetClientRect(
    hwnd: HWND,
    rect: *RECT,
) callconv(.winapi) BOOL;
pub extern "user32" fn SetWindowTextW(
    hwnd: HWND,
    text: LPCWSTR,
) callconv(.winapi) BOOL;

pub extern "user32" fn DefWindowProcW(
    hwnd: HWND,
    msg: UINT,
    wparam: WPARAM,
    lparam: LPARAM,
) callconv(.winapi) LRESULT;
pub extern "user32" fn GetMessageW(
    msg: *MSG,
    hwnd: ?HWND,
    filter_min: UINT,
    filter_max: UINT,
) callconv(.winapi) BOOL;
pub extern "user32" fn PeekMessageW(
    msg: *MSG,
    hwnd: ?HWND,
    filter_min: UINT,
    filter_max: UINT,
    remove: UINT,
) callconv(.winapi) BOOL;
pub extern "user32" fn TranslateMessage(msg: *const MSG) callconv(.winapi) BOOL;
pub extern "user32" fn DispatchMessageW(msg: *const MSG) callconv(.winapi) LRESULT;
pub extern "user32" fn PostQuitMessage(code: c_int) callconv(.winapi) void;
pub extern "user32" fn PostMessageW(
    hwnd: ?HWND,
    msg: UINT,
    wparam: WPARAM,
    lparam: LPARAM,
) callconv(.winapi) BOOL;

pub extern "user32" fn SetWindowLongPtrW(
    hwnd: HWND,
    index: c_int,
    value: LONG_PTR,
) callconv(.winapi) LONG_PTR;
pub extern "user32" fn GetWindowLongPtrW(
    hwnd: HWND,
    index: c_int,
) callconv(.winapi) LONG_PTR;

pub extern "user32" fn GetDC(hwnd: ?HWND) callconv(.winapi) ?HDC;
pub extern "user32" fn ReleaseDC(
    hwnd: ?HWND,
    hdc: HDC,
) callconv(.winapi) c_int;

// SetWindowPos flags.
pub const SWP_NOZORDER: UINT = 0x0004;
pub const SWP_NOACTIVATE: UINT = 0x0010;
pub extern "user32" fn SetWindowPos(
    hwnd: HWND,
    insert_after: ?HWND,
    x: c_int,
    y: c_int,
    cx: c_int,
    cy: c_int,
    flags: UINT,
) callconv(.winapi) BOOL;

pub extern "user32" fn GetDpiForWindow(hwnd: HWND) callconv(.winapi) UINT;
pub extern "user32" fn SetProcessDpiAwarenessContext(
    context: DPI_AWARENESS_CONTEXT,
) callconv(.winapi) BOOL;
pub extern "user32" fn AdjustWindowRectExForDpi(
    rect: *RECT,
    style: DWORD,
    has_menu: BOOL,
    ex_style: DWORD,
    dpi: UINT,
) callconv(.winapi) BOOL;

pub extern "user32" fn GetKeyState(vkey: c_int) callconv(.winapi) i16;
pub extern "user32" fn ValidateRect(
    hwnd: ?HWND,
    rect: ?*const RECT,
) callconv(.winapi) BOOL;

/// MapVirtualKey translations: virtual key -> scan code, virtual key -> char.
pub const MAPVK_VK_TO_VSC: UINT = 0;
pub const MAPVK_VK_TO_CHAR: UINT = 2;
pub extern "user32" fn MapVirtualKeyW(
    code: UINT,
    map_type: UINT,
) callconv(.winapi) UINT;
pub extern "user32" fn SetCapture(hwnd: HWND) callconv(.winapi) ?HWND;
pub extern "user32" fn ReleaseCapture() callconv(.winapi) BOOL;
pub extern "user32" fn TrackMouseEvent(
    event: *TRACKMOUSEEVENT,
) callconv(.winapi) BOOL;
