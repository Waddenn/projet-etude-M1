# Secrets dev-side

Ce dossier centralise les fichiers sensibles utilisés par les scripts de
déploiement (`scripts/02-install-all-parallel.sh`, `scripts/03-switch-nixos.sh`).
**Tout son contenu est gitignored.**

## Fichiers attendus

| Fichier               | Description                                       | Génération                           |
| --------------------- | ------------------------------------------------- | ------------------------------------ |
| `ssh-deploy-key`      | Clé SSH privée pour `nixos-anywhere` / `nixos-rebuild` | `ssh-keygen -t ed25519 -N "" -C projet-etude-k3s -f ssh-deploy-key` |
| `ssh-deploy-key.pub`  | Clé publique correspondante                       | générée avec ci-dessus               |
| `tailscale-authkey`   | Pre-auth key Tailscale (reusable, non-éphémère)   | https://login.tailscale.com/admin/settings/keys |

## Variables d'environnement

Les scripts lisent ces fichiers via :

```bash
export PROJET_K3S_KEY="$(pwd)/secrets/ssh-deploy-key"
export TS_AUTH_KEY_FILE="$(pwd)/secrets/tailscale-authkey"
```

(Ou en restant à la racine de `racine du repo` les valeurs
par défaut pointent déjà ici.)

## In-repo encrypted secrets (sops-nix)

Pour les secrets qui doivent vivre côté cluster (k3s join token, mots de passe
applicatifs Grafana, etc.) le projet utilise **sops-nix**. Voir
`nixos/modules/secrets.nix` et `.sops.yaml` à la racine du dossier nixos.
