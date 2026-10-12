# Kali Linux on airbook (Docker + colima)

Kali runs on `airbook-darwin` as a **container**, not a desktop VM. One command
(`kali`) brings up the stack; everything is lazy, so nothing consumes RAM until
you invoke it.

## Why a container and not a Fusion VM

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
kali --status       # VM, container, and image state
kali --stop         # stop container + shut the VM down (frees ~3 GiB)
kali --rebuild      # rebuild the image from scratch, recreate the container
kali --help
```

`~/kali` on the Mac is mounted at `/root/work` in the container — that's the
path for moving files in and out. It's also the container's working directory.

## First run

The first `kali` does three slow things, once:

1. Creates the colima VM — 2 CPU / 3 GiB RAM / 40 GiB disk, `qemu` VM type
   (not `vz`: this is an Intel Mac on OCLP-patched macOS 15, and qemu + HVF is
   the predictable path).
2. Pulls `kalilinux/kali-rolling` and runs `apt full-upgrade`.
3. Installs the `kali-linux-headless` metapackage — roughly 2 GB of downloads
   and a 4–5 GB image. **Budget 20–40 minutes on this hardware.**

Afterwards startup is just the VM boot (~20 s) plus a `docker exec`.

## What's in it

`kali-linux-headless` — the standard CLI tool set: nmap, metasploit, sqlmap,
hydra, john, aircrack-ng (minus the hardware access), wordlists, and the rest.
Install anything else with plain `apt` inside the container; it survives until
`kali --rebuild`.

The container gets `NET_ADMIN` and `NET_RAW`. Without them nmap can't do SYN
scans and most of the toolset drops to TCP connect scans. The capabilities are
scoped to this container, not granted daemon-wide.

## Where things live

| | |
|---|---|
| Nix definition | `hosts/airbook-darwin/default.nix` (`kaliDockerfile`, `kali` in the `let` block) |
| Packages | `colima`, `docker-client`, `kali` in `environment.systemPackages` |
| colima profile | `kali` (its own profile, **not** the default one) |
| Image / container | `kali-headless:local` / `kali` |
| Shared directory | `~/kali` → `/root/work` |

`docker-client` is CLI-only — the daemon lives inside the colima VM, so there is
nothing Docker-ish running on macOS itself. There is no Docker Desktop here.

To reach the daemon without the wrapper, colima registers a docker context:

```bash
docker --context colima-kali ps
```

## Teardown

```bash
kali --stop                  # just free the RAM
docker rm -f kali            # drop the container, keep the image
colima delete kali           # remove the VM and all 40 GiB of it
```

Because it's a dedicated colima profile, deleting it can't disturb any other
container work on the machine.
