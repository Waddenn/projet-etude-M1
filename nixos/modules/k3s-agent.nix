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
      # Cloud-controller-manager désactivé côté serveur (cf. k3s-server.nix) :
      # il faut aussi désactiver --cloud-provider sur le kubelet sinon le taint
      # node.cloudprovider.kubernetes.io/uninitialized reste sur les workers.
      "--kubelet-arg=cloud-provider="
    ];
  };

  environment.etc."k3s/token" = lib.mkIf (!useSops) {
    text = "change-me-before-production";
    mode = "0600";
  };
}
