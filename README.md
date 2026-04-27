# projet-etude — Cluster k3s GitOps sur Proxmox

Projet d'études M1 DevOps : déploiement reproductible et déclaratif d'un cluster
Kubernetes 3 nœuds (k3s) sur des VMs Proxmox, géré end-to-end avec NixOS,
ArgoCD (GitOps), sops-nix (secrets) et Tailscale (accès distant).

## Stack

| Couche                | Outil                       |
| --------------------- | --------------------------- |
| Hyperviseur           | Proxmox VE                  |
| OS des nœuds          | NixOS 25.11 (flake)         |
| Provisionnement       | nixos-anywhere (kexec)      |
| Cluster Kubernetes    | k3s (1 control-plane, 2 workers) |
| GitOps                | ArgoCD (app of apps)        |
| Secrets               | sops-nix (age via SSH host key) |
| Réseau VPN            | Tailscale + tailscale serve |
| Monitoring            | kube-prometheus-stack + Loki + Alloy |
| Runner de tâches      | just (devShell Nix)         |

## Arborescence

```
.
├── README.md
├── justfile             # tâches projet : just <recipe>
├── docs/                # cahier des charges, cadre pédagogique
├── proxmox/             # scripts côté Proxmox host (clone VMs, installation)
├── nixos/               # flake + modules + hosts (1 source de vérité OS)
│   ├── flake.nix
│   ├── .sops.yaml       # recipients age (dev + 3 VMs)
│   ├── modules/         # common, k3s, tailscale, secrets, k8s-bootstrap…
│   ├── hosts/           # config par nœud (k3s-cp-1, k3s-worker-{1,2})
│   └── secrets/         # secrets sops-encrypted (k3s_token, …)
├── kubernetes/          # manifests synchronisés par ArgoCD
│   └── applications/
│       └── monitoring/  # Applications kube-prometheus-stack + Loki + Alloy
└── secrets/             # secrets dev-side (gitignored, sauf README)
```

## Démarrage rapide

```bash
# 1. DevShell : kubectl, helm, argocd, k9s, sops, age, just, …
nix develop ./nixos

# 2. Déposer les clés dev (cf. secrets/README.md)
#   - secrets/ssh-deploy-key (+ .pub)
#   - secrets/tailscale-authkey

# 3. Pipeline complet (recreate VMs + install NixOS parallèle + GitOps)
just redeploy

# 4. Récupérer le kubeconfig localement
just kubeconfig

# 5. Vérifier
just nodes
just argocd-apps
```

## Accès aux UIs

Une fois le cluster up, les UIs sont exposées sur le tailnet par tailscale serve :

| UI         | URL                                               | Login          |
| ---------- | ------------------------------------------------- | -------------- |
| ArgoCD     | https://k3s-cp-1.<tailnet>.ts.net                | admin / *(cf. `just argocd-password`)* |
| Grafana    | https://k3s-cp-1.<tailnet>.ts.net:8443           | admin / admin  |

## Workflow GitOps

1. Modifier un manifest dans `kubernetes/applications/`.
2. `git push` → ArgoCD détecte le changement → sync automatique (auto-prune + self-heal).
3. Pour un changement OS / cluster : modifier `nixos/`, `git push`, `just switch`.

## Recettes `just`

```bash
just                  # liste tout
just deploy           # nixos-anywhere parallèle sur les 3 VMs
just switch           # nixos-rebuild switch (VMs déjà installées)
just redeploy         # destroy + recreate + deploy
just status           # état des 3 nœuds
just kubeconfig       # pull kubeconfig dans ~/.kube/projet-etude
just argocd-ui        # port-forward UI ArgoCD localhost:8080
just grafana          # port-forward UI Grafana localhost:3000
just sops-init        # générer une age key dev
just sops-edit        # éditer le fichier de secrets encrypté
```

## Sécurité — secrets

- **Secrets dev-side** dans `secrets/` : clé SSH de déploiement, pre-auth Tailscale.
  Gitignored, à rotater hors-bande.
- **Secrets cluster** dans `nixos/secrets/secrets.yaml` : k3s token, futurs mots
  de passe applicatifs. Encryptés avec sops + age. Décryptés au boot par chaque
  nœud via sa SSH host key (dérivée en age via `ssh-to-age`). Ajouter un nœud =
  `just sops-host-keys` puis `just sops-rotate`.
