{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }:

# Scott's standard Bitwarden secrets configuration
# This module defines the common set of secrets and SSH keys used across all machines

{
  services.bitwarden = {
    enable = lib.mkDefault true;

    # SSH keys - same across all machines
    sshKeys = {
      github = {
        user = "scott";
        keyName = "id_ed25519_github";
        itemId = "4eb21873-7ca7-4114-9b0e-b3c90164bc7e";  # BW_Name: github ssh
      };
      legacy = {
        user = "scott";
        keyName = "id_ed25519_legacy";
        itemId = "40b6efe1-5699-46a1-875f-b39800fd3105";  # BW_Name: scott (ssh-ed25519)
      };
      opnsense = {
        user = "scott";
        keyName = "opnsense_admin_ed25519";
        itemId = "21397fb4-104e-4528-90ef-b3ce00fe7c43";  # BW_Name: github ssh
      };
    };

    # Service secrets - same across all machines
    secrets = {
      tailscale_auth_key = {
        name = "tailscale_auth_key";
        itemId = "5cf273b2-68ee-443b-add1-b3c901698464";  # BW_Name: NixOS Machines Auth Key
        field = "tskey";                                   # Custom field in Secure Note
        mode = "0400";
      };
      borg_passphrase = {
        name = "borg_passphrase";
        itemId = "91db7811-ddf1-49aa-8a42-b3d60188a6e6";  # BW_Name: Borg Encryption
        field = "password";
        mode = "0400";
      };
      wazuh_agent_enrollment_password = {
        name = "wazuh_agent_enrollment_password";
        itemId = "TODO-add-bitwarden-item-id";             # BW_Name: Wazuh Agent Enrollment
        field = "password";
        mode = "0400";
      };
    };
  };
}
