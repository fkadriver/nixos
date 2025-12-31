# NixOS Binary Compatibility Fix

## Problem

VSCode extensions with native binaries (like Claude Code) fail to run on NixOS with error:
```
Could not start dynamically linked executable: /path/to/binary
NixOS cannot run dynamically linked executables intended for generic
linux environments out of the box.
```

## Root Cause

NixOS uses a unique filesystem structure that doesn't include standard Linux dynamic linker paths like `/lib64/ld-linux-x86-64.so.2`. Generic Linux binaries expect these paths and fail when they're not present.

## Solution

We use `nix-ld` which provides a compatibility layer for running unpatched dynamic binaries on NixOS.

### Configuration

The fix is implemented in `modules/laptop.nix`:

```nix
programs.nix-ld = {
  enable = true;
  libraries = with pkgs; [
    # Core C/C++ libraries
    stdenv.cc.cc.lib  # libstdc++, libgcc_s

    # Compression libraries
    zlib
    zstd
    bzip2
    xz

    # Crypto and security
    openssl
    libxcrypt
    libxcrypt-legacy

    # Network libraries
    curl
    libssh

    # System libraries
    util-linux
    systemd
    attr
    acl
    libsodium

    # XML/parsing
    libxml2

    # Other common dependencies
    glib
    dbus
  ];
};
```

### How nix-ld Works

- Installs a stub at `/lib64/ld-linux-x86-64.so.2`
- Loads the actual linker via `NIX_LD` environment variable
- Provides library paths via `NIX_LD_LIBRARY_PATH`
- Allows generic Linux binaries to find required libraries

### Applying the Fix

After updating the configuration, rebuild your system:

```bash
# For airbook (with Hyprland + Bitwarden)
sudo nixos-rebuild switch --flake .#airbook

# For latitude (with Hyprland + Bitwarden)
sudo nixos-rebuild switch --flake .#latitude

# For latitude-minimal (with XFCE, no Hyprland/Bitwarden)
sudo nixos-rebuild switch --flake .#latitude-minimal
```

**Note:** The `latitude-minimal` configuration provides XFCE desktop environment instead of Hyprland, and excludes Bitwarden integration.

### Troubleshooting

If a binary still fails to run after applying this fix:

1. **Check what libraries are missing:**
   ```bash
   ldd /path/to/binary
   ```

2. **Find the NixOS package providing a library:**
   ```bash
   nix-locate -w lib/libname.so
   ```

3. **Add the package to `programs.nix-ld.libraries`** in `modules/laptop.nix`

4. **Rebuild the system** to apply changes

### References

- [nix-ld GitHub Repository](https://github.com/nix-community/nix-ld)
- [NixOS Wiki: nix-ld](https://wiki.nixos.org/wiki/Nix-ld)
- [NixOS Wiki: Visual Studio Code](https://wiki.nixos.org/wiki/Visual_Studio_Code)
- [Blog: nix-ld - A clean solution for pre-compiled executables](https://blog.thalheim.io/2022/12/31/nix-ld-a-clean-solution-for-issues-with-pre-compiled-executables-on-nixos/)

## Affected Components

This fix enables:
- VSCode/VSCodium extensions with native binaries
- Claude Code CLI tool
- Other generic Linux binaries that need dynamic linking
