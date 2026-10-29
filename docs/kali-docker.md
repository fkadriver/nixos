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

On airbook that mount crosses two hops (macOS → colima VM via sshfs → the
container), so it is fine for moving files around but slow for heavy random
I/O. Keep hashcat potfiles, large captures and similar inside the container
filesystem and copy results out when done.

## First run

On airbook, the first `kali` does three slow things, once:

1. Creates the colima VM — 2 CPU / 3 GiB RAM / 40 GiB disk, `qemu` VM type
   (not `vz`: this is an Intel Mac on OCLP-patched macOS 15, and qemu + HVF is
   the predictable path).
2. Pulls `kalilinux/kali-rolling` and runs `apt full-upgrade`.
3. Installs the `kali-linux-headless` metapackage. **Budget 30–40 minutes on
   this hardware** (metasploit, hashcat and the full wordlists dominate).

Afterwards startup is just the VM boot (~20 s) plus a `docker exec`.

On NixOS daily drivers there's no VM step — the first `kali` just does steps 2
and 3 against the already-running Docker daemon. Afterwards startup is just
the `docker exec`.

### What it actually costs

Measured after a real build on airbook, not estimated:

| | |
|---|---|
| Image size | **13.5 GB** |
| Packages installed | **1912** (the metapackage names ~200 directly; the rest is dependency closure) |
| colima data disk | **22 GiB used of 40 GiB**, ~16 GiB free |
| VM memory, idle | ~570 MiB of the 3 GiB allocated |

The 40 GiB disk sizing is therefore right but not generous — a second large
image would not fit. Note the VM has two disks: `/` is a fixed 19 GB system
disk, and `/dev/vdb1` is the 40 GiB data disk holding `/var/lib/docker`. Only
the latter is what `--disk 40` sets.

## What's in it

`kali-linux-headless` names ~200 tools directly rather than pulling
`kali-tools-*` groups, so the list below is the whole set, not a starting
point. Source of truth is
[`kali-meta/debian/control`](https://gitlab.com/kalilinux/packages/kali-meta/-/blob/kali/master/debian/control);
the groupings below are ours. Spot-checked against the built image (nmap,
msfconsole, sqlmap, hydra, john, hashcat, aircrack-ng, wifite, radare2, ffuf,
netexec, responder, impacket-*) — all present.

**Recon & enumeration** — `nmap` `masscan` `arp-scan` `netdiscover` `fping`
`hping3` `amass` `theharvester` `recon-ng` `spiderfoot` `dmitry` `fierce`
`dnsenum` `dnsrecon` `dnschef` `nbtscan` `onesixtyone` `snmpcheck` `enum4linux`
`smbmap` `netexec` `ike-scan` `whatweb` `wafw00f` `lbd` `python3-scapy`

**Web** — `sqlmap` `nikto` `wpscan` `ffuf` `gobuster` `dirb` `wfuzz` `skipfish`
`commix` `weevely` `davtest` `cadaver` `mitmproxy` `webshells` `laudanum` `cewl`

**Passwords & hashes** — `hashcat` (+`hashcat-utils`) `john` `hydra` `ncrack`
`patator` `thc-pptp-bruter` `crunch` `maskprocessor` `statsprocessor`
`rsmangler` `pipal` `wordlists` `hashid` `hash-identifier` `chntpw` `samdump2`
`creddump7` `gpp-decrypt`

**Exploitation & post-ex** — `metasploit-framework` (+`msfpc`) `exploitdb`
`impacket-scripts`/`python3-impacket` `mimikatz` `wce` `evil-winrm`
`certipy-ad` `responder` `powershell-empire` `powersploit` `peass`
(linPEAS/winPEAS) `unix-privesc-check` `passing-the-hash` `set`
(Social-Engineer Toolkit) `windows-binaries`

**Sniffing, spoofing, tunneling** — `tcpdump` `netsniff-ng` `ngrep` `tcpick`
`tcpreplay` `netsed` `ssldump` `sslscan` `sslyze` `sslsplit` `qsslcaudit`
`proxychains4` `redsocks` `socat` `sslh` `stunnel4` `dns2tcp` `iodine`
`udptunnel` `ptunnel` `pwnat` `proxytunnel` `rebind` `thc-ipv6` `miredo`
`cryptcat` `dbd` `sbd`

**Reverse engineering & forensics** — `radare2` `binwalk`/`binwalk3` `nasm`
`clang` `upx-ucl` `sleuthkit` `scalpel` `magicrescue` `testdisk`
`bulk-extractor` `scrounge-ntfs` `hashdeep` `pdf-parser` `pdfid` `exiv2`
`libimage-exiftool-perl` `inetsim` `ncurses-hexedit`

**Services you can stand up** — `apache2` `samba` `default-mysql-server` `php`
`snmpd` `openvpn` `vpnc` `atftpd`/`tftp-hpa` `sendemail` `swaks`

Install anything else with plain `apt` inside the container; it survives until
`kali --rebuild`.

### Not included

GUI tools, which live in `kali-linux-default` via `kali-tools-top10`: **Burp
Suite**, **Wireshark**, **Maltego**, `zenmap`, `legion`, `autopsy`,
`hydra-gtk`, `sqlitebrowser`, `starkiller`, `fern-wifi-cracker`, `ophcrack`,
`guymager`, `dirbuster`, `faraday`, `cutycapt`, `gophish`.

## Gotchas inside the container

**No systemd.** `/usr/bin/systemctl` exists — systemd comes in as a dependency —
but it cannot work, because the container runs `sleep infinity` as PID 1:

```
System has not been booted with systemd as init system (PID 1). Can't operate.
```

Use `service` and the sysv scripts in `/etc/init.d/` instead. Metasploit in
particular needs its database started by hand before the first `msfconsole`:

```bash
service postgresql start && msfdb init
service apache2 start
```

`/etc/init.d/` carries scripts for postgresql, mariadb, apache2, nginx, smbd,
nmbd, snmpd, openvpn, ssh, atftpd, iodined, miredo, ptunnel, redsocks, sslh,
inetsim and bluetooth.

**`rockyou.txt` ships gzipped.** Decompress before first use:

```bash
gunzip /usr/share/wordlists/rockyou.txt.gz
```

Other wordlists under `/usr/share/wordlists/`: `dirb`, `fasttrack.txt`,
`john.lst`, `metasploit`, `nmap.lst`, `sqlmap.txt`, `wfuzz`, `wifite.txt`.

**Raw sockets work, via capabilities.** The container gets `NET_ADMIN` and
`NET_RAW`, which is what `nmap -sS`, `masscan`, `hping3`, `arp-scan`,
`netdiscover`, `scapy` and `tcpdump` need. Without them most of the toolset
silently degrades to TCP connect scans. Scoped to this container, not granted
daemon-wide.

**Wireless tools are installed but can't reach hardware.** `aircrack-ng`,
`wifite`, `reaver`, `bully`, `pixiewps`, `kismet`, `iw`, `rfkill`,
`macchanger`, plus `bluez`/`spooftooph` for Bluetooth — all present, none
usable as configured. The wrapper runs the container on the default bridge
network, so `ip link` inside it shows only `lo` and `eth0`; there is no
wireless interface to put into monitor mode.

The ceiling differs by host, though:

- **airbook** — genuinely impossible. The kernel is the colima VM's and there
  is no USB passthrough into it, so a Wi-Fi adapter never appears. Monitor-mode
  work means the installed VMware Fusion 25.
- **NixOS daily drivers** — reachable in principle. Docker runs natively, so
  the host kernel does see a plugged-in adapter; it would need the container
  run with host networking (`--net=host`) and likely `--privileged`. The
  wrapper deliberately doesn't do that — add it per-invocation if you need it,
  rather than widening the default.

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
