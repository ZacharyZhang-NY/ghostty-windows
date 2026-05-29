//! Native Windows application runtime. Owns Win32 windows and their WGL OpenGL
//! contexts and drives the Ghostty core directly (no GTK/embedding layer).
const internal_os = @import("../os/main.zig");

pub const App = @import("win32/App.zig");
pub const Surface = @import("win32/Surface.zig");
pub const resourcesDir = internal_os.resourcesDir;

test {
    _ = App;
    _ = Surface;
}
