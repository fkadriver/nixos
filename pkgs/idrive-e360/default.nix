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
}:

# This package can be built in two ways:
# 1. From a URL (if you have a direct download link from iDrive)
# 2. From a local .deb file (recommended - download from your iDrive console)
#
# To use a local file, build with:
#   nix-build -E 'with import <nixpkgs> {}; callPackage ./pkgs/idrive-e360/default.nix { src = /path/to/idrive360.deb; }'

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

    # Create wrapper scripts for main Perl scripts in bin/
    # Based on inspection, the main scripts are .pl files in /opt/idrive360/

    # Main entry point script (wrapper)
    cat > $out/bin/idrive360 <<'WRAPPER'
    #!/usr/bin/env bash
    IDRIVE_DIR="${lib.getBin placeholder "out"}/share/idrive360"
    cd "$IDRIVE_DIR"
    exec ${perl}/bin/perl "$IDRIVE_DIR/account_setting.pl" "$@"
    WRAPPER
    chmod +x $out/bin/idrive360

    # Backup script wrapper
    cat > $out/bin/idrive360-backup <<'WRAPPER'
    #!/usr/bin/env bash
    IDRIVE_DIR="${lib.getBin placeholder "out"}/share/idrive360"
    cd "$IDRIVE_DIR"
    exec ${perl}/bin/perl "$IDRIVE_DIR/Backup_Script.pl" "$@"
    WRAPPER
    chmod +x $out/bin/idrive360-backup

    # Restore script wrapper
    cat > $out/bin/idrive360-restore <<'WRAPPER'
    #!/usr/bin/env bash
    IDRIVE_DIR="${lib.getBin placeholder "out"}/share/idrive360"
    cd "$IDRIVE_DIR"
    exec ${perl}/bin/perl "$IDRIVE_DIR/Restore_Script.pl" "$@"
    WRAPPER
    chmod +x $out/bin/idrive360-restore

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
