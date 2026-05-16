# Architecture

## Vue d'ensemble

```
┌─────────────┐     git push      ┌──────────────┐
│  Développeur │ ───────────────► │ GitHub       │
└──────┬──────┘                   │ (manifests)  │
       │ just redeploy            └──────┬───────┘
       ▼                                  │ pull
┌─────────────┐                           ▼
│  Proxmox    │                    ┌──────────────┐
│  3 × NixOS  │ ◄── k3s manifests ─│ ArgoCD       │
└──────┬──────┘                    └──────┬───────┘
       │                                  │ sync
       │ Tailscale serve                  ▼
       ▼                           ┌──────────────┐
┌─────────────┐                    │ Workloads    │
│  Accès UIs  │                    │ app + plateforme │
└─────────────┘                    └──────────────┘
```

## Bootstrap du cluster

1. **Proxmox** crée 3 VMs depuis un template NixOS (`proxmox/create-vms.sh`).
2. **nixos-anywhere** installe le flake sur chaque nœud (`proxmox/install-nixos.sh`).
   - Injecte Tailscale auth key et SSH host keys persistantes (`secrets/host-keys/`).
3. **k3s server** (cp-1) démarre ; le module `k8s-bootstrap.nix` dépose dans
   `/var/lib/rancher/k3s/server/manifests/` :
   - namespace + install ArgoCD (pin flake `argo-cd` v2.13.0)
   - Service NodePort ArgoCD (30443)
   - Root Application → `kubernetes/applications/`
4. **ArgoCD** synchronise les Applications enfants (monitoring, security, platform…).
5. **ApplicationSet `apps`** crée une Application par dossier sous `kubernetes/apps/`.

## Flux GitOps application

```
┌────────────────┐    build.yml     ┌──────┐
│ projet-etude-  │ ───────────────► │ GHCR │
│ app-demo       │                  └──┬───┘
└────────────────┘                     │ digest
                                       ▼
                              ┌─────────────────┐
                              │ Image Updater   │
                              │ (commit git)    │
                              └────────┬────────┘
                                       ▼
                              kustomization.yaml
                              (digests api/worker)
                                       ▼
                              ArgoCD sync → cluster
```

## Réseau et exposition

| Port tailscale serve | Cible | Service |
| -------------------- | ----- | ------- |
| 443 | localhost:30443 | ArgoCD NodePort |
| 8443 | localhost:30030 | Grafana NodePort |
| 9443 | localhost:30880 | Traefik (apps métier) |

Configuration : `nixos/modules/tailscale-serve.nix` + `k3s-cp-1.nix`.

## Secrets (3 niveaux)

| Niveau | Mécanisme | Exemples |
| ------ | --------- | -------- |
| Poste dev | Fichiers gitignored `secrets/` | ssh-deploy-key, tailscale-authkey |
| Nœuds NixOS | sops-nix → `/run/secrets/` | k3s_token, discord webhook, deploy key |
| Cluster runtime | Vault + ESO | oidc-client, app-session |

## Observabilité

- **Métriques** : ServiceMonitor api/worker → Prometheus.
- **Logs** : Alloy → Loki ; derived field `trace_id` → Tempo.
- **Traces** : OTLP gRPC → Tempo ; propagation dans PostgreSQL (`jobs.trace_context`).
- **Alertes** : PrometheusRule SLO → Alertmanager → Discord.
- **Énergie** : Kepler DaemonSet → métriques consommation.

## Application de démo

Composants déployés (`kubernetes/apps/projet-etude-app-demo/`) :

| Ressource | Rôle |
| --------- | ---- |
| deployment-api | API HTTP, métriques, endpoints chaos |
| deployment-worker | Consommation file jobs + traces |
| CloudNative-PG | PostgreSQL 16 |
| HPA (api + worker) | Autoscaling CPU |
| Ingress | Routage `/app-demo` via Traefik |
| CronJob audit-purge | Purge logs > 90 j |
| PrometheusRule | SLO + burn-rate |
| chaos.yaml | CronJob killer (suspendu par défaut) |

Code source : [projet-etude-app-demo](https://github.com/Waddenn/projet-etude-app-demo).
