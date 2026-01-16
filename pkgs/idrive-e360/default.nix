{ lib
, stdenv
, autoPatchelfHook
, fetchurl
, dpkg
, makeWrapper
, curl
, coreutils
, gnutar
, gzip
, cron
, bash
, openssl
, zlib
, sqlite
, perl
, perlPackages
, inetutils  # for hostname
, ncurses    # for clear, tput
, unzip
, which
, popt       # for EVS binary (idevsutil_dedup)
, expat      # for bundled Python
, xz         # for bundled Python (liblzma)
, bzip2      # for bundled Python
}:

# This package can be built in two ways:
# 1. From a URL (if you have a direct download link from iDrive)
# 2. From a local .deb file (recommended - download from your iDrive console)
#
# To use a local file, build with:
#   nix-build -E 'with import <nixpkgs> {}; callPackage ./pkgs/idrive-e360/default.nix { src = /path/to/idrive360.deb; }'

let
  runtimePath = lib.makeBinPath [ coreutils inetutils ncurses bash perl unzip which curl gnutar gzip ];
in
stdenv.mkDerivation rec {
  pname = "idrive-e360";
  version = "2025.12.04"; # Based on file timestamps in the package

  # Source can be overridden by passing 'src' parameter
  # Example: callPackage ./pkgs/idrive-e360 { src = /path/to/local/file.deb; }
  src = fetchurl {
    # Direct download URL from iDrive e360 console
    # Replace BBAVCS39384 with your actual account ID from the console
    url = "https://webapp.idrive360.com/api/v1/download/setup/deb/BBAVCS39384?encryption=false";
    sha256 = "06h2fcp5yng2ypv6da0f831by22xym4bfvxz7px6xb6pzg3w6s4s";
    name = "IDrive360.deb";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    dpkg
    makeWrapper
  ];

  buildInputs = [
    stdenv.cc.cc.lib
    openssl
    zlib
    sqlite
    curl
    popt    # Required by EVS binary (idevsutil_dedup)
    expat   # Required by bundled Python (libpython3.5m.so needs libexpat.so.1)
    xz      # Required by bundled Python (liblzma.so.5)
    bzip2   # Required by bundled Python (libbz2.so.1.0)
  ];

  # Don't strip binaries (may break the iDrive client)
  dontStrip = true;

  # Ignore missing dependencies for bundled binaries
  # - libperl.so: iDrive bundles Perl binaries for various distros but we use system Perl
  # - libapt-pkg: Ubuntu-specific package manager library, not used on NixOS
  # - libreadline.so.6/libmpdec.so.2: Old versions not available on NixOS, but these
  #   are for optional Python modules (readline, decimal) not used by iDrive
  autoPatchelfIgnoreMissingDeps = [
    "libperl.so.5.20"
    "libperl.so*"
    "libapt-pkg.so.5.0"  # Ubuntu-specific, not needed
    "libreadline.so.6"   # NixOS has newer version, optional module
    "libmpdec.so.2"      # NixOS has newer version (libmpdec.so.4), optional module
  ];

  unpackPhase = ''
    runHook preUnpack
    dpkg-deb -x $src .
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    # Create directory structure
    mkdir -p $out/{bin,lib,share/idrive360}

    # Copy all iDrive360 files to share directory
    cp -r opt/idrive360/* $out/share/idrive360/

    # Extract EVS binaries from tar.gz files so autoPatchelfHook can patch them
    # The bundled tar files contain idevsutil_dedup which needs libpopt.so
    pushd $out/share/idrive360/Idrivelib/dependencies/evsbin
    for tarfile in *.tar.gz; do
      if [ -f "$tarfile" ]; then
        dirname="''${tarfile%.tar.gz}"
        mkdir -p "$dirname"
        tar -xzf "$tarfile" -C "$dirname"
        rm "$tarfile"
      fi
    done
    popd

    # Extract Python binary for x86_64
    # iDrive uses a bundled Python-based binary for API requests
    # It expects the binary at Idrivelib/dependencies/python/idrive360
    mkdir -p $out/share/idrive360/Idrivelib/dependencies/python
    if [ -f "$out/share/idrive360/Idrivelib/dependencies/pythonbin/k3/x86_64/python.tar.gz" ]; then
      tar -xzf "$out/share/idrive360/Idrivelib/dependencies/pythonbin/k3/x86_64/python.tar.gz" \
        -C $out/share/idrive360/Idrivelib/dependencies/python --strip-components=1
      chmod +x $out/share/idrive360/Idrivelib/dependencies/python/idrive360
    fi

    # Patch account_setting.pl to not set BACKGROUND mode
    # This allows interactive output to display properly
    substituteInPlace $out/share/idrive360/account_setting.pl \
      --replace-fail "\$AppConfig::callerEnv = 'BACKGROUND';" "\$AppConfig::callerEnv = 'INTERACTIVE';"

    # Re-enable authentication flow in account_setting.pl
    # The e360 enterprise version has authentication disabled (commented with #-)
    # and replaced with code that just loads existing credentials.
    # We need to restore the original authentication prompts for first-time setup.
    # Step 1: Uncomment the original auth code (remove #- prefix)
    sed -i 's/^#-\t/\t/g' $out/share/idrive360/account_setting.pl
    # Step 2: Comment out the TODO: NEW section that bypasses auth
    sed -i '/^# TODO: NEW$/,/^# TODO: NEW-end$/{
      /^# TODO: NEW$/b
      /^# TODO: NEW-end$/b
      s/^\t/#-\t/
    }' $out/share/idrive360/account_setting.pl

    # Patch hardcoded perl path to use system perl
    # The original points to /opt/idrive360/Idrivelib/dependencies/perl/perl which doesn't exist on NixOS
    substituteInPlace $out/share/idrive360/Idrivelib/lib/AppConfig.pm \
      --replace-fail 'our $perlBin              = "/opt/idrive360/Idrivelib/dependencies/perl/perl";' \
                     'our $perlBin              = "${perl}/bin/perl";'

    # Fix hardcoded 'root' user - use whoami instead to detect actual user
    # This allows the script to work correctly when run as non-root users
    substituteInPlace $out/share/idrive360/Idrivelib/lib/AppConfig.pm \
      --replace-fail '# our $mcUser = `whoami`;
our $mcUser = "root";' \
                     'our $mcUser = `whoami`;
# our $mcUser = "root";'

    # Create a setup script that creates a mutable runtime directory
    # iDrive needs to write .serviceLocation and other files to its app directory
    # Since Nix store is read-only, we create a mutable copy in ~/.idrive360-app
    cat > $out/bin/idrive360-setup <<'SETUPSCRIPT'
#!/usr/bin/env bash
set -e
IDRIVE_APP_DIR="$HOME/.idrive360-app"
IDRIVE_STORE_DIR="STORE_PATH_PLACEHOLDER"
IDRIVE_SERVICE_DIR="$HOME/idriveIt"

# Create mutable app directory if it doesn't exist
if [ ! -d "$IDRIVE_APP_DIR" ]; then
    echo "Setting up iDrive360 runtime directory at $IDRIVE_APP_DIR..."
    mkdir -p "$IDRIVE_APP_DIR"
    # Copy the entire share directory to make it writable
    cp -r "$IDRIVE_STORE_DIR"/* "$IDRIVE_APP_DIR/"
    chmod -R u+w "$IDRIVE_APP_DIR"
    echo "Setup complete."
fi

# Ensure EVS binary is installed in the service directory
# The iDrive Perl scripts expect idevsutil_dedup at ~/idriveIt/
if [ ! -f "$IDRIVE_SERVICE_DIR/idevsutil_dedup" ]; then
    echo "Installing EVS binary to $IDRIVE_SERVICE_DIR..."
    mkdir -p "$IDRIVE_SERVICE_DIR"

    # Detect architecture and copy appropriate binary
    ARCH=$(uname -m)
    EVS_BIN=""
    if [[ "$ARCH" == "x86_64" || "$ARCH" == "amd64" ]]; then
        EVS_BIN="$IDRIVE_APP_DIR/Idrivelib/dependencies/evsbin/x86_64/idevsutil_dedup"
    elif [[ "$ARCH" == "i386" || "$ARCH" == "i686" ]]; then
        EVS_BIN="$IDRIVE_APP_DIR/Idrivelib/dependencies/evsbin/x86/idevsutil_dedup"
    fi

    if [ -n "$EVS_BIN" ] && [ -f "$EVS_BIN" ]; then
        cp "$EVS_BIN" "$IDRIVE_SERVICE_DIR/idevsutil_dedup"
        chmod +x "$IDRIVE_SERVICE_DIR/idevsutil_dedup"
        echo "EVS binary installed."
    else
        echo "Warning: Could not find EVS binary for architecture $ARCH"
    fi
fi

# Run account_setting.pl from the mutable directory
cd "$IDRIVE_APP_DIR"
exec perl account_setting.pl "$@"
SETUPSCRIPT
    substituteInPlace $out/bin/idrive360-setup \
      --replace-fail "STORE_PATH_PLACEHOLDER" "$out/share/idrive360"
    chmod +x $out/bin/idrive360-setup

    # Main entry point - runs setup and interactive config
    cat > $out/bin/idrive360 <<'MAINSCRIPT'
#!/usr/bin/env bash
IDRIVE_APP_DIR="$HOME/.idrive360-app"
IDRIVE_SERVICE_DIR="$HOME/idriveIt"

if [ ! -d "$IDRIVE_APP_DIR" ]; then
    exec "$(dirname "$0")/idrive360-setup" "$@"
fi

# Ensure EVS binary is installed (may be needed after package upgrade)
if [ ! -f "$IDRIVE_SERVICE_DIR/idevsutil_dedup" ]; then
    mkdir -p "$IDRIVE_SERVICE_DIR"
    ARCH=$(uname -m)
    EVS_BIN=""
    if [[ "$ARCH" == "x86_64" || "$ARCH" == "amd64" ]]; then
        EVS_BIN="$IDRIVE_APP_DIR/Idrivelib/dependencies/evsbin/x86_64/idevsutil_dedup"
    elif [[ "$ARCH" == "i386" || "$ARCH" == "i686" ]]; then
        EVS_BIN="$IDRIVE_APP_DIR/Idrivelib/dependencies/evsbin/x86/idevsutil_dedup"
    fi
    if [ -n "$EVS_BIN" ] && [ -f "$EVS_BIN" ]; then
        cp "$EVS_BIN" "$IDRIVE_SERVICE_DIR/idevsutil_dedup"
        chmod +x "$IDRIVE_SERVICE_DIR/idevsutil_dedup"
    fi
fi

cd "$IDRIVE_APP_DIR"
exec perl account_setting.pl "$@"
MAINSCRIPT
    chmod +x $out/bin/idrive360

    # Backup script wrapper - uses mutable directory
    cat > $out/bin/idrive360-backup <<'BACKUPSCRIPT'
#!/usr/bin/env bash
IDRIVE_APP_DIR="$HOME/.idrive360-app"
if [ ! -d "$IDRIVE_APP_DIR" ]; then
    echo "Error: iDrive360 not configured. Run 'idrive360' first to set up."
    exit 1
fi
cd "$IDRIVE_APP_DIR"
exec perl Backup_Script.pl "$@"
BACKUPSCRIPT
    chmod +x $out/bin/idrive360-backup

    # Restore script wrapper - uses mutable directory
    cat > $out/bin/idrive360-restore <<'RESTORESCRIPT'
#!/usr/bin/env bash
IDRIVE_APP_DIR="$HOME/.idrive360-app"
if [ ! -d "$IDRIVE_APP_DIR" ]; then
    echo "Error: iDrive360 not configured. Run 'idrive360' first to set up."
    exit 1
fi
cd "$IDRIVE_APP_DIR"
exec perl Restore_Script.pl "$@"
RESTORESCRIPT
    chmod +x $out/bin/idrive360-restore

    # Wrap all scripts with proper PATH
    for script in idrive360 idrive360-setup idrive360-backup idrive360-restore; do
      wrapProgram $out/bin/$script --prefix PATH : ${runtimePath}
    done

    # Make all Perl scripts in share/idrive360 executable
    chmod +x $out/share/idrive360/*.pl

    # Set proper permissions for EVS binaries (now in subdirectories after extraction)
    find $out/share/idrive360/Idrivelib/dependencies/evsbin -type f -name 'idevsutil*' -exec chmod +x {} \;

    runHook postInstall
  '';

  meta = with lib; {
    description = "iDrive e360 endpoint backup client for Linux";
    homepage = "https://www.idrive.com/endpoint-backup/";
    license = licenses.unfree;
    platforms = platforms.linux;
    maintainers = [ ];
  };
}
