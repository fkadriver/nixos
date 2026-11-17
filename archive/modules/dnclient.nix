# Defined Networking Managed Nebula client (dnclient) — Tailscale replacement
#
# Control plane is https://admin.defined.net (free tier, 100 hosts); the data
# plane is plain nebula, peer-to-peer. Importing this module installs and runs
# dnclient; enrollment is a one-time imperative step per host:
#
#   1. Create the host at https://admin.defined.net/hosts (assign role/IP;
#      lighthouses additionally get a static public IP + UDP 4242)
#   2. sudo dnclient enroll -code <code-from-admin-panel>
#
# State (keys, certs, config from the control plane) lives in /var/lib/defined
# and survives rebuilds. dnclient polls api.defined.net once a minute for
# config updates. See docs/nebula.md.
#
# Self-hosted fallback: modules/nebula.nix (unused) runs the same mesh without
# the defined.net control plane, with certs from our own CA in sops.
{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }:
let
  version = "0.9.5";
  sources = {
    x86_64-linux = {
      url = "https://dl.defined.net/764f2278/v${version}/linux/amd64/dnclient";
      hash = "sha256-PVBvut7iNtNPdSGf8C5HUplJZwT8nU2s/cf1XWEikvU=";
    };
    aarch64-linux = {
      url = "https://dl.defined.net/764f2278/v${version}/linux/arm64/dnclient";
      hash = "sha256-wgE5+W2qKrUmYw1uCCbehK1NeLQ+2NkWaLrygrGZN9I=";
    };
  };
  # Static Go binary; runs on NixOS without patching
  dnclient = pkgs.stdenvNoCC.mkDerivation {
    pname = "dnclient";
    inherit version;
    src = pkgs.fetchurl sources.${pkgs.stdenv.hostPlatform.system};
    dontUnpack = true;
    installPhase = ''
      install -Dm755 $src $out/bin/dnclient
    '';
    meta = {
      description = "Defined Networking Managed Nebula client";
      homepage = "https://docs.defined.net/glossary/dnclient/";
      platforms = builtins.attrNames sources;
    };
  };
in
{
  config = {
    environment.systemPackages = [ dnclient ];

    systemd.services.dnclient = {
      description = "Defined Networking Managed Nebula client";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "notify";
        NotifyAccess = "main";
        ExecStart = "${dnclient}/bin/dnclient run";
        Restart = "always";
        RestartSec = 5;
        # dnclient defaults its state dir to /var/lib/defined
        StateDirectory = "defined";
      };
      # Before enrollment there is no config; the unit restart-loops until
      # `dnclient enroll` has been run once. Harmless, but expected.
    };

    # Nebula's firewall (managed via defined.net roles) governs mesh traffic;
    # don't double-filter locally. Interface name verified on latitude.
    networking.firewall.trustedInterfaces = [ "defined1" ];
  };
}
