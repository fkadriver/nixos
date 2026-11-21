# VideoProc Converter AI under Wine (experimental)

VideoProc Converter AI (Digiarty) ships only for Windows and macOS. This
documents an attempt to run the Windows build on latitude through Wine. The
native tools in `modules/video-tools.nix` are the supported path. This page
only tracks how far Wine gets.

## Setup

Enabled on latitude via `programs.videoprocWine.enable = true`
(`modules/videoproc-wine.nix`). It uses Wine **staging** (overridable with
`programs.videoprocWine.winePackage`) and a dedicated prefix at
`~/.local/share/videoproc-wine` (override with `VIDEOPROC_PREFIX`), so it can't
interfere with the FORScan or games prefixes.

```bash
# 1. Download the Windows installer from videoproc.com
videoproc install ~/Downloads/videoproc-converter-ai.exe
# 2. Launch (also in the app menu as "VideoProc Converter AI (Wine)")
videoproc
# Launch with a Wine error/DLL-load log written to ~/videoproc-wine.log
videoproc debug
```

The prefix is set to Windows 10 on creation, since the installer refuses older
versions. If the main exe isn't found automatically, set `VIDEOPROC_EXE` to its
full path.

## Things to try, in order

1. **Installer runs and the app opens.** If the window is black or blank:
   `videoproc winetricks dxvk` (D3D11 → Vulkan), then relaunch.
2. **License activation.** Online activation goes through its own embedded
   browser/HTTP stack. If that fails, check `videoproc debug` for
   `wininet`/`winhttp` or `mshtml` errors.
3. **Plain conversion with hardware acceleration OFF** (Settings → disable
   GPU acceleration). This is the most likely part to work, since it's
   bundled ffmpeg running on the CPU.
4. **Hardware encode.** Expected to fail: Intel QSV needs the Windows Intel
   media driver, which Wine doesn't provide. Use VA-API natively instead
   (see `video-tools.nix`).
5. **AI features** (Super Resolution, Frame Interpolation, Stabilization).
   Probably use DirectML/ONNX on a Windows GPU device; expect them to fail or
   fall back to very slow CPU. The native equivalents are `video2x` and
   `upscayl`.

Things that help if you get stuck: `videoproc winetricks vcrun2022`,
`videoproc winetricks corefonts`, and `videoproc reset` to start from a clean
prefix.

## Results

| Date | Step | Result | Notes |
|------|------|--------|-------|
| | | | |
