{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }:

let
  # Headless Kali Linux in a Docker container — the NixOS counterpart to
  # airbook-darwin's colima-based setup (hosts/airbook-darwin/default.nix,
  # docs/kali-docker.md). Same image and wrapper interface; no VM layer here
  # because NixOS daily drivers already run the Docker daemon natively
  # (virtualisation.docker.enable, modules/common.nix) — colima exists on
  # macOS purely to give it a Linux VM to run that daemon in.
  #
  # No --no-install-recommends: Kali's metapackages lean on Recommends for
  # the actual tools, same reasoning as the airbook image.
  kaliDockerfile = pkgs.writeText "Dockerfile.kali" ''
    FROM kalilinux/kali-rolling

    ENV DEBIAN_FRONTEND=noninteractive

    RUN apt-get update \
     && apt-get -y full-upgrade \
     && apt-get -y install kali-linux-headless \
     && apt-get clean \
     && rm -rf /var/lib/apt/lists/*

    WORKDIR /root/work
    CMD ["/bin/zsh", "-l"]
  '';

  # `kali` — builds the image on first use and drops into a persistent
  # container. Lazy: nothing runs until the command is actually invoked.
  # No VM bring-up step (unlike airbook's version) since the Docker daemon
  # is already running as a systemd service on this host.
  kali = pkgs.writeShellScriptBin "kali" ''
    set -euo pipefail

    PATH="${pkgs.docker}/bin:${pkgs.coreutils}/bin:$PATH"

    IMAGE=kali-headless:local
    CONTAINER=kali
    WORKDIR="$HOME/kali"

    usage() {
      cat <<USAGE
    kali — Kali Linux (headless) in a Docker container

      kali                enter a zsh shell in the container (creates it if needed)
      kali <cmd> [args]   run a single command inside the container
      kali --status       show container and image state
      kali --stop         stop the container
      kali --rebuild      rebuild the image from scratch and recreate the container

    Files: $HOME/kali is mounted at /root/work in the container.
    USAGE
    }

    build_image() {
      echo "==> building $IMAGE: pulls ~2 GB of Kali packages, expect 20-40 min first time" >&2
      docker build -t "$IMAGE" - < ${kaliDockerfile}
    }

    # NET_ADMIN/NET_RAW are what let nmap do SYN scans and the rest of the
    # toolset open raw sockets; without them most of Kali degrades to TCP
    # connect scans. Scoped to this container, not the daemon.
    create_container() {
      mkdir -p "$WORKDIR"
      docker run -dit \
        --name "$CONTAINER" \
        --hostname kali \
        --cap-add NET_ADMIN --cap-add NET_RAW \
        -v "$WORKDIR:/root/work" \
        "$IMAGE" sleep infinity >/dev/null
    }

    case "''${1:-}" in
      -h|--help)
        usage
        exit 0
        ;;
      --status)
        docker ps -a --filter "name=^/$CONTAINER$" \
          --format 'container {{.Names}}: {{.Status}}'
        docker image inspect "$IMAGE" >/dev/null 2>&1 \
          && echo "image $IMAGE: present" \
          || echo "image $IMAGE: not built"
        exit 0
        ;;
      --stop)
        docker stop "$CONTAINER" >/dev/null 2>&1 || true
        exit 0
        ;;
      --rebuild)
        docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
        docker image rm -f "$IMAGE" >/dev/null 2>&1 || true
        build_image
        create_container
        echo "==> rebuilt. Run 'kali' to enter." >&2
        exit 0
        ;;
    esac

    docker image inspect "$IMAGE" >/dev/null 2>&1 || build_image

    if ! docker container inspect "$CONTAINER" >/dev/null 2>&1; then
      create_container
    elif [ "$(docker container inspect -f '{{.State.Running}}' "$CONTAINER")" != "true" ]; then
      docker start "$CONTAINER" >/dev/null
    fi

    if [ "$#" -eq 0 ]; then
      exec docker exec -it -w /root/work "$CONTAINER" /bin/zsh -l
    fi
    exec docker exec -it -w /root/work "$CONTAINER" "$@"
  '';
in
{
  config = {
    environment.systemPackages = [ kali ];
  };
}
