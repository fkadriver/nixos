{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }: {
  config = {
    # WiFi configuration for JEN_ACRES
    networking.networkmanager.ensureProfiles = {
      profiles = {
        JEN_ACRES = {
          connection = {
            id = "JEN_ACRES";
            type = "wifi";
            autoconnect = "true";
          };
          wifi = {
            mode = "infrastructure";
            ssid = "JEN_ACRES";
          };
          wifi-security = {
            key-mgmt = "wpa-psk";
            psk = "goatcheese93";
          };
          ipv4 = {
            method = "auto";
          };
          ipv6 = {
            method = "auto";
          };
        };
      };
    };
  };
}
