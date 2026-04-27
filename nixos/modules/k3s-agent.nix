{ config, lib, ... }:

let
  useSops = config.projet.secrets.enable;
in
{
  services.k3s = {
    enable = true;
    role = "agent";
    serverAddr = "https://192.168.1.61:6443";
    tokenFile = if useSops then config.sops.secrets.k3s_token.path else "/etc/k3s/token";
    extraFlags = [
      "--node-ip=${config.projet.k3s.nodeIp}"
    ];
  };

  environment.etc."k3s/token" = lib.mkIf (!useSops) {
    text = "change-me-before-production";
    mode = "0600";
  };
}
