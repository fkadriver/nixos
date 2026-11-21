{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }:

# Native Linux replacements for VideoProc Converter AI (Windows/macOS only):
# conversion, AI upscaling/interpolation, quick cuts, editing and downloads,
# plus the Intel VA-API driver so ffmpeg/HandBrake/kdenlive can hardware-encode.
#
# HandBrake itself stays in daily-driver.nix (every daily driver gets it).
#
# Intel notes (latitude = Kaby Lake, Gen9.5):
#   - VA-API via intel-media-driver (iHD) works for H.264/HEVC decode+encode.
#     Check with `vainfo`; encode with e.g.
#       ffmpeg -vaapi_device /dev/dri/renderD128 -i in.mov \
#         -vf 'format=nv12,hwupload' -c:v hevc_vaapi -qp 24 out.mp4
#   - QSV through oneVPL (vpl-gpu-rt) needs Tiger Lake or newer, so it is not
#     installed here; Kaby Lake's QSV would need the EOL intel-media-sdk.
#   - The ncnn/Vulkan AI tools (video2x, realesrgan, upscayl) run on the iGPU
#     through Mesa's ANV driver. They work, but expect minutes per clip.
let
  cfg = config.programs.videoTools;
in
{
  options.programs.videoTools = {
    enable = lib.mkEnableOption "video conversion, AI upscaling and editing tools";

    intelVaapi = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install intel-media-driver (iHD) for VA-API hardware encode/decode on Intel Gen9+ GPUs.";
    };
  };

  config = lib.mkIf cfg.enable {
    hardware.graphics = {
      enable = true;
      extraPackages = lib.optionals cfg.intelVaapi [ pkgs.intel-media-driver ];
    };

    environment.sessionVariables = lib.mkIf cfg.intelVaapi {
      LIBVA_DRIVER_NAME = "iHD";
    };

    environment.systemPackages = with pkgs; [
      # Convert / compress / inspect
      ffmpeg-full
      mediainfo
      libva-utils            # vainfo: confirm VA-API encode profiles

      # AI upscaling and frame interpolation (ncnn + Vulkan)
      video2x                # video upscale (Real-ESRGAN/Real-CUGAN) + RIFE interpolation
      realesrgan-ncnn-vulkan # CLI image/frame upscaler
      upscayl                # GUI image upscaler

      # Cut / merge / edit
      losslesscut-bin        # lossless trim and merge, no re-encode
      shotcut
      kdePackages.kdenlive   # also has stabilization (vidstab) and denoise effects

      # Download
      yt-dlp
      parabolic              # GUI for yt-dlp
    ];
  };
}
