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
  version = "1.0.0"; # Update this based on your downloaded version

  # Default source - you'll need to replace this with either:
  # 1. A direct download URL from your iDrive e360 console, or
  # 2. Override 'src' to point to a locally downloaded .deb file
  src = fetchurl {
    # PLACEHOLDER - Replace with actual URL from your iDrive e360 console
    # Get this from: https://www.idrive.com/endpoint-backup/ -> Add Devices -> Linux tab
    url = "https://www.idrive.com/downloads/idrive360-linux-latest.deb";
    sha256 = lib.fakeSha256; # Will fail on first build - update with actual hash
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
    mkdir -p $out/{bin,lib,share}

    # Copy iDrive files (adjust paths based on actual .deb structure)
    # These paths may vary - inspect your .deb with: dpkg-deb -c idrive360.deb
    if [ -d opt/idrive360 ]; then
      cp -r opt/idrive360/* $out/
    elif [ -d usr/local/idrive360 ]; then
      cp -r usr/local/idrive360/* $out/
    elif [ -d usr/bin ]; then
      cp -r usr/bin/* $out/bin/
    fi

    # Look for the main binary and create wrapper
    # Common locations: idrive360, IDriveE2Backup, idevsutil, etc.
    for binary in $out/bin/* $out/*bin $out/scripts/*; do
      if [ -f "$binary" ] && [ -x "$binary" ]; then
        wrapProgram "$binary" \
          --prefix PATH : ${lib.makeBinPath [ curl coreutils gnutar gzip cron bash perl ]} \
          --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ openssl zlib sqlite stdenv.cc.cc.lib ]}
      fi
    done

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
