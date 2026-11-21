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

  # Two-pass vid.stab stabilization (ffmpeg-full is built with libvidstab):
  # pass 1 (vidstabdetect) analyses camera motion into a .trf file, pass 2
  # (vidstabtransform) smooths it and re-encodes. Works on any footage,
  # no gyro metadata needed.
  stabilize = pkgs.writeShellScriptBin "stabilize" ''
    set -euo pipefail
    ffmpeg=${pkgs.ffmpeg-full}/bin/ffmpeg

    usage() {
      cat >&2 <<EOF
usage: stabilize [-s shakiness] [-m smoothing] [-z zoom] [-c crf] input [output]

  -s  shakiness 1-10 (default 5; raise for very shaky handheld/walking footage)
  -m  smoothing window in frames (default 15; larger = steadier, more "floaty")
  -z  extra zoom percent to hide moving borders (default 0 = auto optimal zoom)
  -c  x264 CRF quality, lower is better (default 18)

Output defaults to <input>_stabilized.<ext> next to the input. Audio is copied.
EOF
      exit 2
    }

    shakiness=5 smoothing=15 zoom=0 crf=18
    while getopts "s:m:z:c:h" opt; do
      case "$opt" in
        s) shakiness="$OPTARG" ;;
        m) smoothing="$OPTARG" ;;
        z) zoom="$OPTARG" ;;
        c) crf="$OPTARG" ;;
        *) usage ;;
      esac
    done
    shift $((OPTIND - 1))
    [ $# -ge 1 ] && [ $# -le 2 ] || usage

    in="$1"
    [ -f "$in" ] || { echo "stabilize: no such file: $in" >&2; exit 1; }
    ext="''${in##*.}"
    out="''${2:-''${in%.*}_stabilized.$ext}"

    # vidstab's filter-option parser chokes on ':' in paths, so keep the
    # transform file somewhere predictable.
    work="$(mktemp -d)"
    trap 'rm -rf "$work"' EXIT
    trf="$work/transforms.trf"

    echo "[1/2] analysing motion ..." >&2
    "$ffmpeg" -hide_banner -loglevel error -stats -i "$in" \
      -vf "vidstabdetect=shakiness=$shakiness:accuracy=15:result=$trf" \
      -f null -

    if [ "$zoom" = 0 ]; then zoomopts="optzoom=1"; else zoomopts="optzoom=0:zoom=$zoom"; fi

    echo "[2/2] stabilizing -> $out" >&2
    "$ffmpeg" -hide_banner -loglevel error -stats -i "$in" \
      -vf "vidstabtransform=input=$trf:smoothing=$smoothing:$zoomopts:interpol=bicubic,unsharp=5:5:0.8:3:3:0.4" \
      -c:v libx264 -preset slow -crf "$crf" -pix_fmt yuv420p \
      -c:a copy -map_metadata 0 -movflags +faststart \
      "$out"
  '';
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

      # Stabilization
      stabilize              # `stabilize clip.mp4`: two-pass ffmpeg vid.stab, any footage
      gyroflow               # GUI, uses gyro metadata (GoPro/DJI/Insta360/phone) for best results

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
