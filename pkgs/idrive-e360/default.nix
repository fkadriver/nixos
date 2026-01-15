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
  ];

  # Don't strip binaries (may break the iDrive client)
  dontStrip = true;

  # Ignore missing libperl.so dependencies - iDrive bundles its own Perl
  # binaries for various distros but we use the system Perl instead
  autoPatchelfIgnoreMissingDeps = [ "libperl.so.5.20" "libperl.so*" ];

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

    # Patch account_setting.pl to not set BACKGROUND mode
    # This allows interactive output to display properly
    substituteInPlace $out/share/idrive360/account_setting.pl \
      --replace-fail "\$AppConfig::callerEnv = 'BACKGROUND';" "\$AppConfig::callerEnv = 'INTERACTIVE';"

    # Create a setup script that creates a mutable runtime directory
    # iDrive needs to write .serviceLocation and other files to its app directory
    # Since Nix store is read-only, we create a mutable copy in ~/.idrive360-app
    cat > $out/bin/idrive360-setup <<'SETUPSCRIPT'
#!/usr/bin/env bash
set -e
IDRIVE_APP_DIR="$HOME/.idrive360-app"
IDRIVE_STORE_DIR="STORE_PATH_PLACEHOLDER"

# Create mutable app directory if it doesn't exist
if [ ! -d "$IDRIVE_APP_DIR" ]; then
    echo "Setting up iDrive360 runtime directory at $IDRIVE_APP_DIR..."
    mkdir -p "$IDRIVE_APP_DIR"
    # Copy the entire share directory to make it writable
    cp -r "$IDRIVE_STORE_DIR"/* "$IDRIVE_APP_DIR/"
    chmod -R u+w "$IDRIVE_APP_DIR"
    echo "Setup complete."
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
if [ ! -d "$IDRIVE_APP_DIR" ]; then
    exec "$(dirname "$0")/idrive360-setup" "$@"
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

    # Set proper permissions for subdirectories
    chmod +x $out/share/idrive360/Idrivelib/dependencies/evsbin/*

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
