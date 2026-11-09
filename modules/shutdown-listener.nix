# Authenticated remote-shutdown listener, for Home Assistant's closet
# high-temp automation to trigger a graceful poweroff on this host. HA
# Green's Core container has no SSH client and sits on a different VLAN
# (IoT) than this host, so rather than punching a firewall hole (the thing
# this project consistently avoids - see the NAS backup NFS export routed
# over Tailscale instead), HA reaches this listener over Tailscale via a
# plain HTTP POST with a bearer token.
#
# Also doubles as a status mirror: HA pushes the closet temp to /status on
# every sensor update, which this writes to a local file - lets you check
# the closet temp (and whether it's above the shutdown threshold) directly
# on this host via the `closet-status` command, no HA round-trip needed.
#
# Scoped deliberately narrow: Tailscale-only (firewalled per-interface, not
# just bound-address - avoids a race with the interface coming up), two
# fixed paths, one fixed destructive action (poweroff), constant-time token
# comparison.
{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }:

let
  cfg = config.services.shutdownListener;
  statusPath = "/var/lib/shutdown-listener/status.json";

  listenerScript = pkgs.writeText "shutdown-listener.py" ''
    import sys, hmac, json, os, time, subprocess
    from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

    port = int(sys.argv[1])
    token = open(sys.argv[2]).read().strip()
    status_path = sys.argv[3]

    class Handler(BaseHTTPRequestHandler):
        def _authed(self):
            supplied = self.headers.get("Authorization", "").removeprefix("Bearer ")
            return hmac.compare_digest(supplied, token)

        def do_POST(self):
            if not self._authed():
                self.send_response(403)
                self.end_headers()
                return

            if self.path == "/shutdown":
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b"shutting down\n")
                # Delay so this HTTP response actually reaches the caller
                # before the host goes down, instead of the connection
                # just dying.
                subprocess.Popen(["systemd-run", "--on-active=2s", "systemctl", "poweroff"])
            elif self.path == "/status":
                length = int(self.headers.get("Content-Length", 0))
                try:
                    payload = json.loads(self.rfile.read(length))
                except ValueError:
                    self.send_response(400)
                    self.end_headers()
                    return
                payload["received_at"] = int(time.time())
                tmp = status_path + ".tmp"
                with open(tmp, "w") as f:
                    json.dump(payload, f)
                os.replace(tmp, status_path)
                self.send_response(200)
                self.end_headers()
            else:
                self.send_response(404)
                self.end_headers()

        def log_message(self, fmt, *args):
            sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))

    ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()
  '';

  closetStatusScript = pkgs.writeText "closet-status.py" ''
    import json, sys, time

    try:
        with open(sys.argv[1]) as f:
            data = json.load(f)
    except (FileNotFoundError, ValueError):
        print("No closet status received from HA yet.")
        sys.exit(0)

    age = int(time.time()) - data.get("received_at", 0)
    temp = data.get("temp")
    flag = " - ABOVE SHUTDOWN THRESHOLD" if data.get("above_threshold") else ""
    print(f"Closet temp: {temp}F (updated {age}s ago){flag}")
  '';

  closetStatusBin = pkgs.writeShellScriptBin "closet-status" ''
    exec ${pkgs.python3}/bin/python3 ${closetStatusScript} ${statusPath}
  '';
in
{
  options.services.shutdownListener = {
    enable = lib.mkEnableOption "Tailscale-only authenticated remote-shutdown listener for HA automations";

    port = lib.mkOption {
      type = lib.types.port;
      default = 9090;
      description = "TCP port to listen on (Tailscale interface only).";
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets."shutdown_listener_token" = { };

    environment.systemPackages = [ closetStatusBin ];

    systemd.services.shutdown-listener = {
      description = "Authenticated remote-shutdown listener (Tailscale-only)";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" "tailscaled.service" ];
      serviceConfig = {
        ExecStart = "${pkgs.python3}/bin/python3 ${listenerScript} ${toString cfg.port} ${config.sops.secrets."shutdown_listener_token".path} ${statusPath}";
        Restart = "on-failure";
        StateDirectory = "shutdown-listener";
        # Needs root to call poweroff - the token + Tailscale-only firewall
        # scoping are the real access boundary here, not local privilege.
      };
    };

    networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ cfg.port ];
  };
}
