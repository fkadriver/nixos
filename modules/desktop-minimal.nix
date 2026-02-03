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

    # Set boot label
    system.nixos.label = "Desktop";

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

    # Minimal desktop applications - focused on photo and AI processing
    environment.systemPackages = with pkgs; [
      # Development & AI tools
      python3
      python3Packages.pip
      python3Packages.virtualenv
      git
      vscode-fhs  # VSCode with FHS environment for AI tools

      # KDE essentials
      kdePackages.dolphin          # File manager
      kdePackages.konsole          # Terminal
      kdePackages.kate             # Text editor
      kdePackages.gwenview         # Image viewer
      kdePackages.okular           # PDF viewer
      kdePackages.spectacle        # Screenshot tool
      kdePackages.ark              # Archive manager

      # Photo processing
      gimp
      darktable                    # RAW photo processor
      # AI/ML will be added via Python environments

      # Essential utilities
      firefox
      vlc
    ];

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
