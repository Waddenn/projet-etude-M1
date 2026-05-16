# Cahier des charges — projet-etude M1 DevOps

## Contexte

Projet d'études visant à concevoir, déployer et opérer un cluster Kubernetes
reproductible sur infrastructure personnelle (Proxmox), en appliquant les
pratiques DevOps / SRE / Green IT.

## Objectifs

1. **Infrastructure as Code** : configuration OS déclarative (NixOS flake).
2. **GitOps** : état du cluster décrit dans Git, synchronisé par ArgoCD.
3. **Sécurité** : gestion des secrets (sops-nix, Vault, ESO), scan images, auth OIDC.
4. **Observabilité** : métriques, logs, traces corrélées, SLO et alerting.
5. **Résilience** : autoscaling, chaos engineering, démonstration en soutenance.
6. **Green IT** : visibilité consommation (Kepler).

## Périmètre

### Inclus

- 3 nœuds k3s (1 CP, 2 workers) sur Proxmox.
- Stack plateforme : ArgoCD, monitoring, logs, traces, Vault/Dex/ESO, CNPG, Kepler.
- Application de démo multi-composants (api, worker, audit-purge).
- CI validation infra + CI build/scan app.
- Livraison continue des images (GHCR + Image Updater).
- Documentation et scénario de démo.

### Hors périmètre

- Haute disponibilité multi control-plane.
- Multi-cluster / fédération.
- Production-grade Vault (mode DEV accepté).
- Backup automatisé PostgreSQL (recommandé post-M1).

## Critères d'acceptation

| # | Critère | Vérification |
| - | ------- | ------------ |
| 1 | Cluster déployable en une commande (`just redeploy`) | Démo live ou logs |
| 2 | Toutes les Applications ArgoCD `Synced` + `Healthy` | `just argocd-apps` |
| 3 | App accessible via Tailscale + OIDC | `just app-demo-url` |
| 4 | Dashboards Grafana importés | UI Grafana |
| 5 | Alerte SLO déclenchable | `just demo-flaky` |
| 6 | Autoscaling observable | `just loadtest` + `just hpa-watch` |
| 7 | Chaos sans perte durable | `just chaos-kill` + `just chaos-probe` |
| 8 | CI infra verte sur `main` | Badge GitHub Actions |
| 9 | Secrets non commités en clair | `.gitignore` + sops |
| 10 | Documentation à jour | README, AUDIT, docs/ |

## Livrables

- Dépôt infra : `projet-etude-M1` (ce repo).
- Dépôt application : `projet-etude-app-demo`.
- Documentation : README, AUDIT.md, docs/.
- Soutenance : scénario [`demo-soutenance.md`](./demo-soutenance.md).

## Contraintes techniques

- NixOS 25.11, k3s, ArgoCD 2.13.
- Accès distant via Tailscale uniquement (pas d'exposition publique directe).
- Ressources VM : 2 vCPU, 6 GiB RAM, 32 Go disque par nœud.

## Planning indicatif (référence)

| Phase | Contenu |
| ----- | ------- |
| 1 | Proxmox + NixOS + k3s |
| 2 | ArgoCD + apps plateforme |
| 3 | App démo + CNPG |
| 4 | Observabilité + SLO |
| 5 | Sécurité + chaos + doc |
