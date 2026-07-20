{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }:

{
  services.bitwarden.secrets.container_ts_authkey = {
    name = "container_ts_authkey";
    itemId = "3fcd8301-f2b8-4376-a4cc-b48d015b1ea5";  # BW_Name: Tailscale Container AUTH key
    field = "ts_authkey";
    mode = "0400";
  };
}
