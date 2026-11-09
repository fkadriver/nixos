# Authenticated remote-shutdown listener, for Home Assistant's closet
# high-temp automation to trigger a graceful poweroff on this host. HA
# Green's Core container has no SSH client and sits on a different VLAN
# (IoT) than this host, so rather than punching a firewall hole (the thing
# this project consistently avoids - see the NAS backup NFS export routed
# over Tailscale instead), HA reaches this listener over Tailscale via a
# plain HTTP POST with a bearer token.
#
# Scoped deliberately narrow: Tailscale-only (firewalled per-interface, not
# just bound-address - avoids a race with the interface coming up), one
# fixed path, one fixed action (poweroff), constant-time token comparison.
{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }:

let
  cfg = config.services.shutdownListener;

  listenerScript = pkgs.writeText "shutdown-listener.py" ''
    import sys, hmac, subprocess
    from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

    port = int(sys.argv[1])
    token = open(sys.argv[2]).read().strip()

    class Handler(BaseHTTPRequestHandler):
        def do_POST(self):
            if self.path != "/shutdown":
                self.send_response(404)
                self.end_headers()
                return
            supplied = self.headers.get("Authorization", "").removeprefix("Bearer ")
            if not hmac.compare_digest(supplied, token):
                self.send_response(403)
                self.end_headers()
                return
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"shutting down\n")
            # Delay so this HTTP response actually reaches the caller before
            # the host goes down, instead of the connection just dying.
            subprocess.Popen(["systemd-run", "--on-active=2s", "systemctl", "poweroff"])

        def log_message(self, fmt, *args):
            sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))

    ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()
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

    systemd.services.shutdown-listener = {
      description = "Authenticated remote-shutdown listener (Tailscale-only)";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" "tailscaled.service" ];
      serviceConfig = {
        ExecStart = "${pkgs.python3}/bin/python3 ${listenerScript} ${toString cfg.port} ${config.sops.secrets."shutdown_listener_token".path}";
        Restart = "on-failure";
        # Needs root to call poweroff - the token + Tailscale-only firewall
        # scoping are the real access boundary here, not local privilege.
      };
    };

    networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ cfg.port ];
  };
}
