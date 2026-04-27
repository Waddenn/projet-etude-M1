{ lib, ... }:

{
  services.tailscale = {
    enable = true;
    # Clé déposée par nixos-anywhere via --extra-files (cf. 02-install-all-parallel.sh).
    # Si le fichier est absent, le service démarre quand même mais le node n'est pas
    # connecté tant qu'un `tailscale up` manuel n'a pas été fait.
    authKeyFile = lib.mkDefault "/var/lib/tailscale/auth.key";
    # Active le routage et l'IP forwarding nécessaires pour que k3s puisse
    # exposer ses services via Tailscale (subnet routes, exit node, etc.).
    useRoutingFeatures = "both";
    extraUpFlags = [
      "--ssh"
      "--accept-dns=false"
    ];
  };

  networking.firewall = {
    trustedInterfaces = [ "tailscale0" ];
    allowedUDPPorts = [ 41641 ];
    checkReversePath = "loose";
  };
}
