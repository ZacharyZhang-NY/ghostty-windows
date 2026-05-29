# Ghostty on Windows

A native Windows build of [Ghostty](https://ghostty.org): a Win32 window with a
WGL-backed OpenGL renderer, driving the upstream Ghostty core (ConPTY shell,
FreeType/DirectWrite font discovery, GPU cell rendering).

## Install

Download `ghostty-setup-x86_64.exe` and run it:

- from the latest [release](../../releases), or
- from the artifacts of a [Windows workflow run](../../actions/workflows/windows.yml).

It installs per-user (no administrator required) with a Start Menu shortcut and
an uninstaller.

## Build from source

Requires [Zig 0.15.2](https://ziglang.org/download/).

```sh
zig build -Dtarget=x86_64-windows-gnu -Dapp-runtime=win32 --release=fast
```

This produces `zig-out\bin\ghostty.exe` with resources under `zig-out\share`.
`ghostty.exe` discovers its resources relative to its own location, so the
`bin` and `share` directories must stay siblings.

### Build the installer

Requires [Inno Setup 6](https://jrsoftware.org/isinfo.php).

```sh
ISCC /DBuildDir=zig-out /DAppVersion=1.3.2 dist\windows\ghostty.iss
```

This produces `dist\windows\output\ghostty-setup-x86_64.exe`.

## Continuous integration

`.github/workflows/windows.yml` builds the release executable and the installer
on every push to `main` and on manual dispatch, uploading
`ghostty-setup-x86_64.exe` as a workflow artifact. Pushing a `v*` tag (for
example `v1.3.2`) additionally publishes a GitHub Release with the installer
attached.
