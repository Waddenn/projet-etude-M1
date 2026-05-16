# Secrets dev-side

Ce dossier centralise les fichiers sensibles utilisés par les scripts
`proxmox/install-nixos.sh`, `proxmox/switch-nixos.sh` et les recettes `just`.
**Tout son contenu est gitignored** (sauf ce README).

## Fichiers attendus

| Fichier / dossier | Description | Génération |
| ----------------- | ----------- | ---------- |
| `ssh-deploy-key` | Clé SSH privée pour `nixos-anywhere` / `nixos-rebuild` | `ssh-keygen -t ed25519 -N "" -C projet-etude-k3s -f secrets/ssh-deploy-key` |
| `ssh-deploy-key.pub` | Clé publique (injectée dans les VMs Proxmox) | générée avec ci-dessus |
| `tailscale-authkey` | Pre-auth key Tailscale (reusable, non éphémère) | [Tailscale admin → Keys](https://login.tailscale.com/admin/settings/keys) |
| `host-keys/<hostname>/` | SSH host keys persistantes par nœud | `just sops-bootstrap` (via `proxmox/bootstrap-host-keys.sh`) |

Les host keys persistantes évitent de casser le déchiffrement sops-nix à chaque
`just recreate` : les mêmes clés sont réinjectées dans les VMs neuves.

## Variables d'environnement

Le `justfile` charge un `.env` à la racine du repo (voir `.env.example`) :

```bash
export SECRETS_DIR="$(pwd)/secrets"
export PROJET_K3S_KEY="$SECRETS_DIR/ssh-deploy-key"
export TS_AUTH_KEY_FILE="$SECRETS_DIR/tailscale-authkey"
export KUBECONFIG="$HOME/.kube/projet-etude"
```

## Secrets cluster (sops-nix)

Les secrets partagés par le cluster vivent dans `nixos/secrets/secrets.yaml`
(chiffré, versionné) :

| Clé sops | Usage |
| -------- | ----- |
| `k3s_token` | Join token k3s (server + agents) |
| `discord_webhook_url` | Alertmanager → Discord |
| `argocd_image_updater_ssh_key_b64` | Deploy key GitHub (write-back digests) |

Workflow :

```bash
just sops-init          # clé age dev locale (~/.config/sops/age/keys.txt)
# Ajouter la pubkey dans nixos/.sops.yaml
just sops-bootstrap     # host keys + alignement recipients
just sops-edit          # éditer secrets.yaml
just sops-rotate        # re-chiffrer après changement de recipients
```

Voir `nixos/modules/secrets.nix` et `nixos/.sops.yaml`.

## Checklist premier déploiement

1. Créer `ssh-deploy-key` et `tailscale-authkey`.
2. `just sops-init` puis ajouter votre clé age dans `nixos/.sops.yaml`.
3. `just sops-bootstrap` (génère `host-keys/` + met à jour sops).
4. Renseigner `discord_webhook_url` et la deploy key Image Updater dans `just sops-edit`.
5. `just redeploy`.
