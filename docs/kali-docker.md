# Kali Linux in Docker (airbook + NixOS daily drivers)

Kali runs as a **container**, not a desktop VM, on both `airbook-darwin` and
the NixOS daily drivers (latitude, via `modules/kali-docker.nix`, imported by
`daily-driver.nix`). One command (`kali`) brings up the stack; everything is
lazy, so nothing consumes resources until you invoke it. Same image
(`kali-linux-headless`) and wrapper interface on both; the only real
difference is the VM layer described below.

## NixOS vs. airbook

On NixOS, `kali` talks directly to the Docker daemon already running natively
via `virtualisation.docker.enable` (`modules/common.nix`) — no VM step, no
`colima`. `--status`/`--stop`/`--rebuild` only manage the container and image.

Everything below (first run, usage, what's in it, teardown) applies the same
way on both; the colima-specific parts (VM creation, `--status` VM line,
`colima delete`) are airbook/macOS-only, called out as such.

## Why a container and not a Fusion VM (airbook)

`airbook` is a MacBookAir7,2: dual-core i5 @1.8 GHz, 8 GB RAM. VMware Fusion 25
*is* installed on it, but a full Kali desktop there wants 3–4 GB and both cores,
leaving the host starved and the guest sluggish. The headless tool set is what
actually gets used on this machine, and it runs comfortably in ~3 GiB.

Being Intel, Kali amd64 runs **natively** either way — there is no emulation
penalty, which is the one hardware advantage this box has over Apple Silicon.

**What you give up:** GUI tools (Burp Suite, Wireshark, Zenmap) and USB Wi-Fi
passthrough, so monitor-mode / packet-injection work is out of reach. Both need a
real VM — use the installed Fusion if that day comes.

## Usage

```bash
kali                # enter a zsh shell in the container (creates it if needed)
kali nmap -sS host  # run a single command inside the container
kali --status       # container/image state (airbook: + colima VM state)
kali --stop         # stop the container (airbook: + shuts the VM down, frees ~3 GiB)
kali --rebuild      # rebuild the image from scratch, recreate the container
kali --help
```

`~/kali` is mounted at `/root/work` in the container on both hosts — that's
the path for moving files in and out. It's also the container's working
directory.

## First run

On airbook, the first `kali` does three slow things, once:

1. Creates the colima VM — 2 CPU / 3 GiB RAM / 40 GiB disk, `qemu` VM type
   (not `vz`: this is an Intel Mac on OCLP-patched macOS 15, and qemu + HVF is
   the predictable path).
2. Pulls `kalilinux/kali-rolling` and runs `apt full-upgrade`.
3. Installs the `kali-linux-headless` metapackage — roughly 2 GB of downloads
   and a 4–5 GB image. **Budget 20–40 minutes on this hardware.**

Afterwards startup is just the VM boot (~20 s) plus a `docker exec`.

On NixOS daily drivers there's no VM step — the first `kali` just does steps 2
and 3 against the already-running Docker daemon. Afterwards startup is just
the `docker exec`.

## What's in it

`kali-linux-headless` — the standard CLI tool set: nmap, metasploit, sqlmap,
hydra, john, aircrack-ng (minus the hardware access), wordlists, and the rest.
Install anything else with plain `apt` inside the container; it survives until
`kali --rebuild`.

The container gets `NET_ADMIN` and `NET_RAW`. Without them nmap can't do SYN
scans and most of the toolset drops to TCP connect scans. The capabilities are
scoped to this container, not granted daemon-wide.

## Where things live

| | airbook | NixOS daily drivers |
|---|---|---|
| Nix definition | `hosts/airbook-darwin/default.nix` (`kaliDockerfile`, `kali` in the `let` block) | `modules/kali-docker.nix`, imported by `daily-driver.nix` |
| Packages | `colima`, `docker-client`, `kali` in `environment.systemPackages` | `kali` in `environment.systemPackages` (Docker CLI/daemon already provided by `common.nix`) |
| VM | dedicated colima profile `kali` (its own profile, **not** the default one) | none — Docker daemon runs natively |
| Image / container | `kali-headless:local` / `kali` | `kali-headless:local` / `kali` |
| Shared directory | `~/kali` → `/root/work` | `~/kali` → `/root/work` |

`docker-client` on airbook is CLI-only — the daemon lives inside the colima
VM, so there is nothing Docker-ish running on macOS itself (no Docker
Desktop). On NixOS, `docker` is the full package since the daemon runs as a
systemd service on the host itself.

To reach the daemon without the wrapper:

```bash
docker --context colima-kali ps   # airbook
docker ps                         # NixOS
```

## Teardown

```bash
kali --stop                  # stop the container (airbook: + frees the colima VM's RAM)
docker rm -f kali             # drop the container, keep the image
colima delete kali            # airbook only — remove the VM and all 40 GiB of it
```

On airbook, because it's a dedicated colima profile, deleting it can't disturb
any other container work on the machine. On NixOS there's no VM to delete —
`docker rm -f kali` and `docker image rm kali-headless:local` is full teardown.
