# Audit technique — projet-etude-M1

Audit factuel du dépôt infra (Mai 2026). Complète le README pour la soutenance
et la revue de code.

## Synthèse

| Domaine | Note | Commentaire |
| ------- | ---- | ----------- |
| Reproductibilité | ★★★★☆ | NixOS flake + scripts Proxmox ; IPs/host hardcodés |
| GitOps | ★★★★★ | Bootstrap ArgoCD via Nix, root app, AppSet, Image Updater |
| Sécurité | ★★★☆☆ | sops-nix solide ; Vault DEV ; pas de mTLS inter-services |
| Observabilité | ★★★★★ | Métriques, logs, traces, SLO burn-rate, dashboards |
| Résilience | ★★★★☆ | HPA, PDB, chaos recipes ; control-plane non HA |
| CI | ★★★★☆ | validate.yml complet ; pas de test e2e cluster en CI |
| Documentation | ★★★★☆ | README + docs/ ; dépend du fork pour reproduire |

## Architecture

### Couches

1. **Hyperviseur** — Proxmox, 3 VMs (301–303), disque via disko.
2. **OS** — NixOS 25.11, modules déclaratifs (k3s server/agent, Tailscale, sops).
3. **Orchestration** — k3s single control-plane + 2 workers.
4. **GitOps** — ArgoCD installé par manifests k3s ; root Application → `kubernetes/applications/` ; ApplicationSet → `kubernetes/apps/*`.
5. **Plateforme** — monitoring (Prometheus stack, Loki, Alloy, Tempo), security (Vault, ESO, Dex, Trivy), data (CNPG), Kepler.
6. **Application** — `projet-etude-app-demo` (images GHCR, digests dans kustomization).

### Points forts

- **Single source of truth** : OS (flake) et workloads (Git) séparés proprement.
- **Secrets at boot** : host keys persistantes + sops-nix évitent le cycle « nouvelle VM = secrets cassés ».
- **SLO opérationnels** : PrometheusRule burn-rate alignée sur le Google SRE Workbook.
- **Chaîne d'observabilité** : métriques → alertes ; logs → traces via `trace_id` ; exemplars Prometheus.
- **Démo intégrée** : endpoints `/flaky`, `/slow`, chaos manifests + recettes `just`.

### Limitations connues

| Limite | Impact | Mitigation possible |
| ------ | ------ | ------------------- |
| 1 seul control-plane | Pas de HA API/etcd | 3 CP + etcd externe (hors périmètre M1) |
| Vault mode DEV | Non production | Vault HA + auto-unseal |
| IPs / hostname figés | Repro ailleurs = édition manuelle | Variables `.env` + templating flake |
| Repo URL en dur | Fork = 2 fichiers à changer | `projet.argocd.repoUrl` via flake input |
| Image Updater → main | Pas de PR, commit direct | Branche dédiée + PR bot |
| Pas de backup CNPG déclaré | Perte données si PV fail | ScheduledBackup CR |
| Windows natif | `just` nécessite bash | WSL2 documenté |

## Sécurité

### Ce qui est en place

- Secrets dev-side gitignored ; sops pour secrets cluster.
- NetworkPolicies sur api/worker ; PDB ; scans Trivy CI + operator.
- OIDC Dex, rôles RBAC applicatifs, session signée.
- Audit log + purge 90 j (RGPD).

### Dettes

- Vault non durci (DEV, pas de policies fines documentées hors cluster).
- Certificats internes souvent `insecure` côté tailscale serve (acceptable lab).
- Deploy key Image Updater : accès write au repo — rotation manuelle via `sops-edit`.
- Pas de Pod Security Standards / admission policies explicites dans l'audit des manifests.

## Observabilité — KPIs

| KPI | Cible / seuil | Source |
| --- | ------------- | ------ |
| Disponibilité HTTP | SLO 99,5 % | `prometheusrule.yaml` |
| Burn-rate fast | 14,4 × budget 1 h | idem |
| Burn-rate slow | 6 × budget 6 h | idem |
| Latence p95 | Alerte dédiée | `demo-slow` + rules |
| Traces bout-en-bout | api → worker | Tempo + OTLP |
| Énergie | Relative (Kepler) | Dashboard plateforme |

## CI/CD

### Infra (`validate.yml`)

- yamllint, actionlint, shellcheck (`proxmox/`)
- kubeconform (CRDs catalog)
- `nix flake check --no-build`
- kube-score sur kustomize app-demo (tests ignorés documentés)

### App (repo séparé)

- Tests Go race + cover ; golangci-lint ; Trivy bloquant ; push GHCR.

### Écart

- Pas de `kubectl kustomize` sur tout `kubernetes/` en CI.
- Pas de test de déploiement cluster automatisé (acceptable pour lab perso).

## Exploitation (runbook condensé)

### Redéploiement complet

```bash
just redeploy
just kubeconfig
just argocd-apps
```

### ArgoCD désynchronisé

```bash
just argocd-sync
kubectl -n argocd describe application <name>
```

### Rotation secret sops

```bash
just sops-edit          # modifier la valeur
just sops-rotate        # si recipients changent
just switch             # propager sur les nœuds
```

### Après `just recreate`

Les host keys dans `secrets/host-keys/` doivent correspondre à `.sops.yaml`.
Si doute : `just sops-bootstrap` puis `just redeploy`.

## Recommandations post-M1

1. Paramétrer IPs / repo via flake `specialArgs` ou `.env` unique.
2. Ajouter job CI `kubectl kustomize` sur `kubernetes/applications` et `apps`.
3. Documenter backup/restore CNPG.
4. Remplacer Vault DEV par instance durcie ou retirer si ESO suffit.
5. Optionnel : environnement éphémère (Terraform Proxmox + même flake).

## Références internes

- Bootstrap ArgoCD : `nixos/modules/k8s-bootstrap.nix`
- Secrets : `nixos/modules/secrets.nix`
- SLO : `kubernetes/apps/projet-etude-app-demo/prometheusrule.yaml`
- ApplicationSet : `kubernetes/applications/platform/apps-applicationset.yaml`
