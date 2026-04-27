{ config, lib, pkgs, ... }:

{
  options.projet.k3s.nodeIp = lib.mkOption {
    type = lib.types.str;
    description = "Adresse IPv4 fixe du noeud K3s.";
  };

  config = {
    system.stateVersion = "25.11";

    boot.kernelModules = [ "br_netfilter" "overlay" ];
    boot.kernel.sysctl = {
      "net.bridge.bridge-nf-call-iptables" = 1;
      "net.bridge.bridge-nf-call-ip6tables" = 1;
      "net.ipv4.ip_forward" = 1;
    };

    networking = {
      useDHCP = false;
      defaultGateway = "192.168.1.254";
      nameservers = [ "1.1.1.1" "9.9.9.9" ];
      interfaces.ens18.ipv4.addresses = [{
        address = config.projet.k3s.nodeIp;
        prefixLength = 24;
      }];
      firewall = {
        enable = true;
        # 22 ssh, 80/443 ingress, 6443 k8s API, 10250 kubelet,
        # 9100 node-exporter (scrapé par Prometheus depuis un autre nœud).
        allowedTCPPorts = [ 22 80 443 6443 10250 9100 ];
        allowedUDPPorts = [ 8472 ];
        # Tout le trafic intra-cluster (CNI flannel) doit passer librement.
        trustedInterfaces = [ "cni0" "flannel.1" ];
      };
    };

    time.timeZone = "Europe/Paris";
    i18n.defaultLocale = "fr_FR.UTF-8";
    console.keyMap = "fr";

    environment.systemPackages = with pkgs; [
      curl
      git
      htop
      jq
      kubectl
      vim
    ];

    services.openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        PermitRootLogin = "no";
      };
    };

    services.qemuGuest.enable = true;
    security.sudo.wheelNeedsPassword = false;

    users.users.ops = {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
      openssh.authorizedKeys.keyFiles = [ ../ssh-authorized-keys.pub ];
    };

    nix.settings = {
      experimental-features = [ "nix-command" "flakes" ];
      trusted-users = [ "root" "@wheel" ];
    };

    projet.secrets.enable = true;
  };
}
