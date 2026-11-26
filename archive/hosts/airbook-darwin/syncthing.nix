{ config, lib, pkgs, ... }: {
  # Syncthing on macOS is installed via Homebrew (not nix-darwin service)
  # This file documents the configuration for manual setup in Syncthing GUI

  # Device ID for airbook-darwin:
  # MIWPTKO-AAFMDLU-BBWGY74-VIR6B2Y-H5OQAV2-COC7RKI-MSS3ZLB-XYBLYQB

  # After starting Syncthing (brew services start syncthing):
  # 1. Access GUI at http://127.0.0.1:8384
  # 2. Add devices: latitude, nas01, iphone
  # 3. Configure folders:
  #    - Documents: ~/Documents (shared with latitude, nas01, iphone)
  #    - Photos: ~/Photos (shared with latitude, nas01)
  #    - Downloads: ~/Downloads (shared with latitude, nas01)
  #    - tmp: ~/tmp (shared with latitude, iphone)

  # Folder versioning: Simple File Versioning, keep 5 versions
}
