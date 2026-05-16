# projet-etude — Cluster k3s GitOps sur Proxmox

Projet d'études M1 DevOps : déploiement reproductible et déclaratif d'un cluster
Kubernetes 3 nœuds (k3s) sur des VMs Proxmox, géré end-to-end avec NixOS,
ArgoCD (GitOps), sops-nix (secrets) et Tailscale (accès distant).

## Stack

| Couche                | Outil                       |
| --------------------- | --------------------------- |
| Hyperviseur           | Proxmox VE (3 VMs : 2 vCPU / 6 GiB / 32 GB) |
| OS des nœuds          | NixOS 25.11 (flake)         |
| Provisionnement       | nixos-anywhere (kexec)      |
| Cluster Kubernetes    | k3s (1 control-plane, 2 workers) |
| GitOps                | ArgoCD + Image Updater (write-back Git, digests épinglés) |
| Secrets cluster       | sops-nix (age dérivé des SSH host keys persistantes) |
| Secrets runtime       | Vault (DEV) + External-Secrets Operator |
| Auth                  | Dex (OIDC IdP) — viewer / operator |
| Réseau VPN            | Tailscale + tailscale serve (HTTPS tailnet) |
| Ingress               | Traefik (intégré k3s) + middleware StripPrefix |
| Métriques             | kube-prometheus-stack 65.5.1 (Prometheus + Alertmanager + Grafana) |
| Logs                  | Loki 6.16 + Alloy 0.10 (DaemonSet) |
| Traces                | Tempo 1.24 (OTLP gRPC, exemplars trace\_id) |
| Sécurité images       | Trivy en CI (CRITICAL/HIGH bloquant) + trivy-operator dans le cluster |
| Green IT              | Kepler (estimation conso énergétique) |
| Base de données       | CloudNative-PG (PostgreSQL 16.4) |
| App de démo           | Go 1.25 — tracker d'incidents (api + worker + audit-purge) |
| CI/CD                 | GitHub Actions (validate.yml infra, build.yml app → GHCR) |
| Runner de tâches      | just (devShell Nix) |

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
│   ├── applications/    # plateforme (Apps Argo CD posées par la root app)
│   │   ├── monitoring/  # kube-prometheus-stack + Loki + Alloy
│   │   └── platform/    # ApplicationSet "apps" + Argo CD Image Updater
│   └── apps/            # apps métier (1 dossier = 1 Application Argo CD via l'AppSet)
│       └── projet-etude-app-demo/  # manifests pointant ghcr.io/waddenn/projet-etude-app-demo
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
| Traefik / app-demo | https://k3s-cp-1.<tailnet>.ts.net:9443/app-demo | OIDC Dex |

## Observabilité & SLO

- **Dashboards Grafana** auto-importés : *Platform overview*, *App demo (métier)*,
  *SLO & burn-rate*, *Worker & queue*.
- **SLO disponibilité** : 99.5 % (burn-rate multi-fenêtres 5m/1h fast + 30m/6h slow,
  cf. `kubernetes/apps/projet-etude-app-demo/prometheusrule.yaml`).
- **Alerting** : Alertmanager → webhook Discord (secret sops + template
  `nixos/modules/secrets.nix`).
- **Traces distribuées** : OTLP gRPC → Tempo, propagation via colonne JSONB
  `jobs.trace_context` jusqu'au worker (span CONSUMER lié).
- **Logs ↔ traces** : derived field `trace_id` Loki → Tempo + retour vers Loki/Prometheus.

## Chaos engineering

Recettes prêtes pour démos de résilience (cf. `just chaos-*`) :

```bash
just chaos-kill          # tue 1 pod api random
just chaos-schedule      # active le CronJob killer (toutes les 30 min)
just chaos-partition     # isole 1 pod via NetworkPolicy deny-all 60 s
just chaos-probe         # 5 min de /healthz à 20 rps pendant chaos
just demo-flaky          # injecte 50 % d'erreurs (déclenche burn-rate fast)
just demo-slow           # injecte 800 ms de latence (déclenche p95 alert)
```

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

- **Secrets dev-side** dans `secrets/` : clé SSH de déploiement, pre-auth Tailscale,
  clé SSH ArgoCD Image Updater, SSH host keys persistantes des 3 nœuds.
  Gitignored, à rotater hors-bande.
- **Secrets cluster** dans `nixos/secrets/secrets.yaml` : k3s token, webhook Discord,
  clé SSH image-updater. Encryptés avec sops + age (4 recipients : dev + 3 hosts).
  Décryptés au boot par chaque nœud via sa SSH host key (dérivée en age via
  `ssh-to-age`). Ajouter un nœud = `just sops-host-keys` puis `just sops-rotate`.
- **Secrets runtime** : Vault (mode DEV) + External-Secrets Operator. Les secrets
  applicatifs (`oidc-client`, `app-session`, `app-webhook`) sont projetés depuis Vault
  via `ClusterSecretStore vault-backend`.
- **App** : OIDC via Dex (rôles `viewer` / `operator`), session cookie signée
  HMAC-SHA256, audit log (purge RGPD 90 j via CronJob hebdomadaire).

## CI/CD

- **`projet-etude` (infra)** — `.github/workflows/validate.yml` : yamllint,
  actionlint, shellcheck, kubeconform, `nix flake check`, kube-score.
- **`projet-etude-app-demo` (app)** — `.github/workflows/build.yml` :
  golangci-lint v2.6, `go test -race -cover`, build matriciel
  (api / worker / audit-purge), scan Trivy bloquant (CRITICAL/HIGH),
  push GHCR avec tags `main` + `sha-<long>`.
- **Livraison continue** : ArgoCD Image Updater détecte les nouveaux digests
  sur GHCR et commit la mise à jour dans `kubernetes/apps/.../kustomization.yaml`
  → resync automatique.

## Audit technique

Un audit factuel complet du projet (architecture, IaC, conteneurisation,
orchestration, sécurité, observabilité, KPIs réels, dette technique) est
disponible dans [`AUDIT.md`](./AUDIT.md).
