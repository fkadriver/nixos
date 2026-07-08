# Nebula Overlay Network (Managed Nebula via defined.net)

Nebula mesh VPN, migrating away from Tailscale. The control plane is
**Managed Nebula** from Defined Networking — free tier, up to 100 hosts, signed
up via the LINUX Unplugged referral link <https://defined.net/unplugged>.
Admin panel: <https://admin.defined.net/hosts>.

Tailscale runs in parallel until everything that references
`*.warthog-royal.ts.net` (NFS mounts, Borg, Wazuh) has been repointed and
roaming is proven.

## How it works

- Each host runs **dnclient** (`modules/dnclient.nix`), a static binary that
  embeds nebula. It enrolls against api.defined.net, then polls once a minute
  for config/cert updates. Data traffic is peer-to-peer nebula; defined.net
  only sees the control plane.
- Certs, keys, and IP assignment are handled by defined.net — no local CA, no
  sops secrets, no cert signing.
- Host firewall rules are managed centrally via **roles** in the admin panel.
- Default network CIDR is `100.100.0.0/22`; IPs are assigned per host in the
  admin panel.
- **Lighthouses are NOT hosted by defined.net** — we still run our own on
  Oracle Cloud (lighthouse01, Always Free instance).

## Enrolling a host

1. Import `inputs.self.nixosModules.dnclient` in the host config and rebuild.
   (The dnclient service will restart-loop until enrollment — expected.)
2. In [admin.defined.net](https://admin.defined.net/hosts): Add host, set the
   name and (optionally) a specific IP and role.
3. Copy the one-time enrollment code, then on the host:
   `sudo dnclient enroll -code <code>`
4. Verify: `systemctl status dnclient`, `ip link` (interface should be
   `defined` — if it differs, fix `trustedInterfaces` in `modules/dnclient.nix`),
   and ping another mesh host.

State persists in `/var/lib/defined` across rebuilds. Non-NixOS hosts (nas01,
airbook-darwin) use defined.net's standard installers.

## lighthouse01 (Oracle Cloud)

1. Create an OCI **Always Free** instance. `VM.Standard.E2.1.Micro` is offered
   in `US-CHICAGO-1-AD-2` (select AD-2 in Placement, then the shape is under
   "Specialty and previous generation"). Ampere A1 also works if capacity
   allows. Consider upgrading the account to Pay-As-You-Go (still $0 within
   free limits) to avoid idle-instance reclamation and capacity walls.
2. Networking: wizard-created VCN + public subnet, auto-assign public IPv4
   (reserved IP preferred). Add a VCN ingress rule: UDP 4242 from 0.0.0.0/0.
   Open UDP 4242 in the OS firewall too.
3. In the admin panel: Add host → mark as **lighthouse**, set its public IP
   (the routable address) and port 4242.
4. Install dnclient on it (defined.net installer for Oracle Linux/Ubuntu, or
   enroll it as a NixOS host in this flake) and enroll with its code.

Until lighthouse01 exists, hosts on the same LAN can still reach each other
(nebula local discovery), but roaming needs the lighthouse; Tailscale covers
roaming meanwhile.

## Migration checklist (Tailscale ➜ Nebula)

- [x] defined.net account (free tier, via defined.net/unplugged)
- [x] `modules/dnclient.nix`, imported by latitude and vm01
- [ ] Rebuild latitude and vm01, create hosts in admin panel, enroll both
- [ ] Create lighthouse01 on OCI, enroll as lighthouse; test latitude off-LAN
- [ ] Enroll remaining hosts (nas01*, OTworkstation, log01, piholes, airbook-darwin)
- [ ] Repoint NFS mounts, Borg repos, Wazuh manager, xrdp firewall rule from
      `*.warthog-royal.ts.net` / `tailscale0` to mesh IPs/names / `defined`
- [ ] Decide name resolution (defined.net DNS features, pihole entries, or
      `networking.hosts` with assigned mesh IPs)
- [ ] Retire `modules/tailscale.nix` from `common.nix`

\* nas01 is Ubuntu — use defined.net's standard install; it's the NFS/Borg
target, so enroll it before repointing those services.

## Self-hosted fallback (unused)

Before adopting Managed Nebula, a fully self-hosted setup was built and still
exists in the repo as a fallback if defined.net ever goes away:

- `modules/nebula.nix` — self-managed mesh (10.100.0.0/24), hostname-based
  enrollment, NOT imported by any host currently
- `secrets/nebula/*.crt` — public certs for a 10-year CA ("jensen-mesh")
- `secrets.yaml` `nebula/*` — CA + host private keys, sops-encrypted

To fall back: swap host imports from `dnclient` back to `nebula` and follow
the enrollment comments in that module (sign certs with the sops-held CA key).
