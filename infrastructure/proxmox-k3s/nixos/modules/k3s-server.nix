{ config, lib, ... }:

let
  useSops = config.projet.secrets.enable;
in
{
  services.k3s = {
    enable = true;
    role = "server";
    tokenFile = if useSops then config.sops.secrets.k3s_token.path else "/etc/k3s/token";
    extraFlags = [
      "--node-ip=${config.projet.k3s.nodeIp}"
      "--advertise-address=${config.projet.k3s.nodeIp}"
      "--write-kubeconfig-mode=0644"
      "--disable=servicelb"
    ];
  };

  # Fallback non-encrypté tant que sops-nix n'est pas en place.
  environment.etc."k3s/token" = lib.mkIf (!useSops) {
    text = "change-me-before-production";
    mode = "0600";
  };
}
