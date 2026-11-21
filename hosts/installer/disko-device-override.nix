# Args come from disko --argstr; disko ignores --arg with --flake, so the
# installer evaluates the flake's disk layout itself and overrides the device.
{ flakeRef, config, device, ... }:
let
  flake = builtins.getFlake flakeRef;
  lib = flake.inputs.nixpkgs.lib;
  # `<host>-bootstrap` (staged install) partitions like `<host>`.
  host = lib.removeSuffix "-bootstrap" config;
  evaluated =
    if flake ? diskoConfigurations && flake.diskoConfigurations ? ${host}
    then flake.diskoConfigurations.${host}.disko.devices
    else flake.nixosConfigurations.${host}.config.disko.devices;
  # The evaluated layout carries disko's generated internals (_create,
  # _mount, ...) and every nested `device` (content, partitions, LVs), all
  # derived from the old disk device. Drop them so disko re-derives them
  # from the disk-level device set below. (None of our layouts set a nested
  # device by hand.)
  strip = v:
    if builtins.isAttrs v
    then lib.mapAttrs (_: strip)
      (lib.filterAttrs (n: _: !(lib.hasPrefix "_" n) && n != "device") v)
    else if builtins.isList v then map strip v
    else v;
  devices = strip evaluated;
in
assert lib.assertMsg (devices.disk ? main)
  "disko layout for ${host} has no disk named 'main'";
{
  disko.devices = devices // {
    disk = lib.mapAttrs (n: d: d // {
      device = if n == "main" then device else evaluated.disk.${n}.device;
    }) devices.disk;
  };
}
