{ config, lib, pkgs, ... }:

let
  cfg = config.projet.tailscaleServe;
in
{
  options.projet.tailscaleServe = {
    enable = lib.mkEnableOption "Configuration déclarative de tailscale serve";

    routes = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      example = lib.literalExpression ''
        {
          "443"  = "https+insecure://localhost:30443";  # ArgoCD UI
          "8443" = "http://localhost:30030";             # Grafana
        }
      '';
      description = ''
        Map des ports HTTPS tailnet vers leurs backends locaux.
        Chaque clé = port (string), chaque valeur = URL backend (http://, https://,
        https+insecure://). Le hostname tailnet est résolu automatiquement.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.tailscale-serve = {
      description = "Apply declarative tailscale serve routes";
      after = [ "tailscaled.service" "tailscaled-autoconnect.service" "network-online.target" ];
      requires = [ "tailscaled.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        # Petit retry: si tailscaled n'a pas encore son hostname, on attend.
        ExecStartPre = pkgs.writeShellScript "tailscale-serve-wait" ''
          set -eu
          for i in $(seq 1 30); do
            if ${pkgs.tailscale}/bin/tailscale status >/dev/null 2>&1; then
              exit 0
            fi
            sleep 2
          done
          echo "tailscaled n'est pas prêt après 60s" >&2
          exit 1
        '';
        ExecStart = pkgs.writeShellScript "tailscale-serve-apply" ''
          set -eu
          ${pkgs.tailscale}/bin/tailscale serve reset
          ${lib.concatStringsSep "\n" (lib.mapAttrsToList (port: target:
            "${pkgs.tailscale}/bin/tailscale serve --bg --https=${port} ${lib.escapeShellArg target}"
          ) cfg.routes)}
          ${pkgs.tailscale}/bin/tailscale serve status
        '';
        # Replay si on touche à la config (changement de routes).
        ExecReload = "/bin/true";
      };
    };
  };
}
