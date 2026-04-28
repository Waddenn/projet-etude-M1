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
        # Webhook Discord pour Alertmanager + ArgoCD notifications.
        # Décrypté seulement sur le control-plane (k3s server) — les agents
        # n'en ont pas besoin, mais sops-nix tente le décryptage sur tous les
        # hôtes ; on garde le secret listé partout, le template est wrap-mkIf
        # pour limiter l'écriture du Secret k8s à cp-1.
        discord_webhook_url = {
          mode = "0400";
          owner = "root";
          group = "root";
        };
        # Clé SSH privée (base64) du deploy key GitHub utilisé par ArgoCD Image
        # Updater pour pusher les digests dans le repo plateforme.
        # Stockée pré-encodée pour éviter les pbs d'indentation multi-ligne YAML
        # dans le template du Secret k8s.
        argocd_image_updater_ssh_key_b64 = {
          mode = "0400";
          owner = "root";
          group = "root";
        };
      };

      # Génération déclarative du Secret k8s consommé par Alertmanager.
      # sops-nix interpole les placeholders au moment du décryptage et
      # écrit le manifest dans le dossier auto-déployé par k3s. Limité au
      # control-plane via lib.mkIf sur projet.argocd.enable.
      templates = lib.mkIf (config.projet.argocd.enable or false) {
        "alertmanager-discord.yaml" = {
          path = "/var/lib/rancher/k3s/server/manifests/30-alertmanager-discord.yaml";
          mode = "0400";
          content = ''
            apiVersion: v1
            kind: Secret
            metadata:
              name: alertmanager-discord-webhook
              namespace: monitoring
            type: Opaque
            stringData:
              # Discord accepte les payloads Slack-format sur l'endpoint /slack.
              webhook-url: "${config.sops.placeholder.discord_webhook_url}/slack"
          '';
        };
        # repo-creds ArgoCD : associe la deploy key SSH au repo plateforme.
        # Le label argocd.argoproj.io/secret-type=repo-creds fait que
        # argocd-server scanne ce Secret et l'utilise pour les sources
        # qui matchent l'URL.
        "argocd-image-updater-ssh.yaml" = {
          path = "/var/lib/rancher/k3s/server/manifests/40-argocd-image-updater-ssh.yaml";
          mode = "0400";
          content = ''
            apiVersion: v1
            kind: Secret
            metadata:
              name: argocd-image-updater-ssh
              namespace: argocd
              labels:
                argocd.argoproj.io/secret-type: repo-creds
            type: Opaque
            stringData:
              type: git
              url: git@github.com:Waddenn/projet-etude-M1.git
            data:
              sshPrivateKey: ${config.sops.placeholder.argocd_image_updater_ssh_key_b64}
          '';
        };
      };
    };
  };
}
