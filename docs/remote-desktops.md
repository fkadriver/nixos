# Remote Desktop Options

## Current Setup (active)

Remote access runs over Tailscale on all hosts. No inbound holes in the ISP
firewall (established policy — see also `docs/nebula.md`).

| Host | Protocol | Notes |
|------|----------|-------|
| latitude | XRDP | KDE Plasma session |
| OTworkstation | XRDP | Openbox session (lightweight for remote use) |
| nas01 | XRDP | Headless; admin access only |

**Client side (latitude):** `x2goclient` is installed for connecting to
OTworkstation via the X2Go protocol as an alternative to XRDP.

XRDP is the primary stack and meets current requirements — no GPU acceleration
needed, sessions are general desktop / admin work.

---

## Alternatives Evaluated (2026-07)

### Sunshine + Moonlight

**What it is:** Sunshine is the open-source host-side GameStream server;
Moonlight is the client. Together they replace NVIDIA's proprietary GameStream
using NVENC hardware video encoding.

**NixOS support:** First-class — there is a native `services.sunshine` module
in nixpkgs:

```nix
services.sunshine = {
  enable = true;
  autoStart = true;
  capSysAdmin = true;   # required for Wayland DRM/KMS capture; omit for Xorg
  openFirewall = true;
};
```

Additional requirements:
- Enable the `uinput` kernel module and add your user to the `uinput` group for
  input device emulation.
- Known issue post-NixOS 25.11: uinput permissions for input capture broke and
  require a custom udev rule to fix.

**Performance:** Best-in-class latency for interactive desktop work. NVENC
hardware encode makes 4K/60 practical. Pairs naturally with Tailscale (same
topology as XRDP, no extra infrastructure).

**Cost:** Free and open source.

**Verdict:** Strong option if GPU-accelerated remote desktop is ever needed
(3D viewport work, gaming, video). Not justified for current general
desktop / admin use — XRDP is simpler and adequate.

---

### NoMachine

**What it is:** Proprietary remote desktop using the NX protocol. Historically
positioned as a faster VNC alternative; has a free personal tier.

**NixOS support:** Partial. The client (`nomachine-client` / nxplayer, v9.5.7)
is in nixpkgs. **The server is not officially packaged for NixOS** — standard
installation scripts fail due to shebang issues and require significant
workarounds. Multiple open NixOS Discourse threads confirm ongoing friction with
the server side.

**Performance:** Uses software encoding by default; higher latency than
Sunshine/Moonlight for GPU-heavy work. Adequate for general desktop use, but
offers no meaningful advantage over XRDP for this workload.

**Cost:** Free tier is proprietary; source not available.

**Verdict:** Not worth pursuing. Poor NixOS server support and no performance
advantage over the current XRDP stack for non-GPU workloads. Client package
exists if ever needed to connect to a NoMachine host elsewhere.

---

## Decision

Staying on XRDP. Requirements are general desktop and admin access with no GPU
acceleration needed. XRDP is well-integrated, declarative in the NixOS config,
and works cleanly over Tailscale.

Revisit Sunshine + Moonlight if GPU-accelerated remote desktop becomes a
requirement (e.g., remote 3D printing / OrcaSlicer sessions from a non-local
machine).
