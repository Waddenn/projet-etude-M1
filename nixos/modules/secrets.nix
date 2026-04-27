{ config, lib, ... }:

let
  cfg = config.projet.secrets;
in
{
  options.projet.secrets = {
    enable = lib.mkEnableOption "Décryptage de secrets via sops-nix sur cette machine";

    file = lib.mkOption {
      type = lib.types.path;
      default = ../secrets/secrets.yaml;
      description = "Chemin vers le fichier sops-encrypted (relatif au flake nixos/).";
    };
  };

  config = lib.mkIf cfg.enable {
    sops = {
      defaultSopsFile = cfg.file;
      defaultSopsFormat = "yaml";

      # Décryptage via la clé SSH host de la VM (dérivée en age via ssh-to-age).
      # La clé doit avoir été déclarée comme recipient dans .sops.yaml lors
      # de l'encryption.
      age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
      # On ne génère pas un fichier age dédié : la SSH host key fait foi.
      age.generateKey = false;

      # Secrets exposés (à compléter au fur et à mesure).
      # Chaque entrée est rendue dans /run/secrets/<nom> avec les permissions
      # demandées, lue par les services correspondants.
      secrets = {
        # Token K3s partagé entre control-plane et agents.
        k3s_token = {
          mode = "0600";
          owner = "root";
          group = "root";
        };
      };
    };
  };
}
