{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }: {
  imports = [
    inputs.self.nixosModules.bitwarden
    inputs.self.nixosModules.bitwarden-scott
    inputs.home-manager.nixosModules.home-manager
    (inputs.self.homeConfigurations.scott).nixosModule
  ];

  config = {
    # Home-manager configuration for scott
    home-manager.useGlobalPkgs = true;
    home-manager.useUserPackages = true;

    # Set boot label (can be overridden by host-specific configs)
    system.nixos.label = lib.mkDefault "Desktop";

    # Enable NetworkManager for network management
    networking.networkmanager.enable = true;

    # Enable KDE Plasma (lightweight and powerful for photo/AI work)
    services.xserver.enable = true;
    services.displayManager.sddm = {
      enable = true;
      wayland.enable = true;
    };
    services.desktopManager.plasma6.enable = true;

    # Enable sound with PipeWire
    security.rtkit.enable = true;
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
    };

    # Minimal desktop applications - focused on programmatic photo processing and AI
    environment.systemPackages = with pkgs; [
      # Development & AI/ML tools
      python3
      python3Packages.pip
      python3Packages.virtualenv
      git
      vscode-fhs  # VSCode with FHS environment for AI tools

      # System libraries for photoAlbumOrganizer and computer vision
      gcc                          # Compiler for native extensions
      opencv                       # Computer vision library
      # Optional: uncomment to compile dlib (face encoding/identity matching)
      # cmake pkg-config openblas lapack dlib

      # KDE essentials
      kdePackages.dolphin          # File manager
      kdePackages.konsole          # Terminal
      kdePackages.kate             # Text editor
      kdePackages.gwenview         # Image viewer for verifying results
      kdePackages.okular           # PDF viewer
      kdePackages.spectacle        # Screenshot tool
      kdePackages.ark              # Archive manager
      kdePackages.filelight        # Disk usage visualizer

      # Essential utilities
      firefox
      vlc

      # Prevent screen blanking/sleep
      caffeine-ng
    ];

    # Auto-start caffeine to prevent screen blanking
    environment.etc."xdg/autostart/caffeine.desktop".text = ''
      [Desktop Entry]
      Name=Caffeine
      Comment=Prevent screen blanking
      Exec=caffeine
      Icon=caffeine
      Terminal=false
      Type=Application
      Categories=Utility;
      X-GNOME-Autostart-enabled=true
    '';

    # Dynamic linking for Python venv C extensions (numpy, opencv, mediapipe, etc.)
    programs.nix-ld = {
      enable = true;
      libraries = with pkgs; [
        stdenv.cc.cc.lib  # libstdc++
        zlib
        glib
        libGL             # OpenCV / mediapipe
        xorg.libxcb       # OpenCV display support
      ];
    };

    # Enable CUDA support for NVIDIA GPUs (if present)
    # Users can uncomment these if they have NVIDIA hardware:
    # hardware.opengl.enable = true;
    # services.xserver.videoDrivers = [ "nvidia" ];
    # hardware.nvidia.modesetting.enable = true;

    # Font configuration for better display
    fonts = {
      enableDefaultPackages = true;
      packages = with pkgs; [
        noto-fonts
        noto-fonts-cjk-sans
        noto-fonts-color-emoji
        liberation_ttf
        fira-code
        fira-code-symbols
      ];
    };
  };
}
