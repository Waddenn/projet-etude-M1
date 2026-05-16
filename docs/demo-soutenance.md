# Scénario de soutenance (~15 minutes)

Script pour démontrer le projet devant un jury. Prérequis : cluster déjà
déployé (`just redeploy` fait avant la séance).

## Avant la soutenance

```bash
nix develop ./nixos
export KUBECONFIG=~/.kube/projet-etude
just kubeconfig    # si besoin
just argocd-apps   # tout doit être Synced/Healthy
```

Ouvrir dans le navigateur (tailnet) :

- ArgoCD : `https://k3s-cp-1.<tailnet>.ts.net`
- Grafana : port `8443` — dashboards *SLO & burn-rate*, *App demo*
- App : `https://k3s-cp-1.<tailnet>.ts.net:9443/app-demo`

## Déroulé

### 1. Introduction (2 min)

- Objectif : cluster GitOps reproductible M1 DevOps.
- Stack : Proxmox → NixOS → k3s → ArgoCD → app Go + observabilité.
- Schéma : [`architecture.md`](./architecture.md) ou README.

### 2. Vérification automatique (2 min)

```bash
just demo
```

Montrer :

- Les 3 nœuds `Ready` (`just nodes`).
- Les Applications ArgoCD vertes.
- L'URL app qui répond.

### 3. GitOps (3 min)

- ArgoCD UI : root app → applications monitoring / platform / apps.
- Montrer `kubernetes/apps/projet-etude-app-demo/kustomization.yaml` (digests épinglés).
- Expliquer le flux : push image CI → GHCR → Image Updater → commit → sync.

### 4. Observabilité & SLO (4 min)

```bash
just demo-flaky rate=0.5 duration=60
```

- Grafana → dashboard *SLO & burn-rate* : hausse du ratio d'erreurs.
- Mentionner SLO 99,5 % et alertes burn-rate (`prometheusrule.yaml`).
- Optionnel : `just demo-slow` pour latence p95.

### 5. Résilience (3 min)

```bash
# Terminal 1
just chaos-probe

# Terminal 2 (pendant la probe)
just chaos-kill
```

- Expliquer PDB, replicas, redémarrage pod.
- Optionnel : `just chaos-partition` (coupure réseau 60 s).

### 6. Charge & autoscaling (2 min)

```bash
# Terminal 1
just loadtest

# Terminal 2
just hpa-watch
```

- Montrer montée des replicas HPA sous charge.

### 7. Conclusion (1 min)

- Points forts : reproductibilité Nix, GitOps, SLO, secrets sops.
- Limites : pas de HA CP, Vault DEV — voir [`AUDIT.md`](../AUDIT.md).

## Commandes de secours

| Problème | Commande |
| -------- | -------- |
| ArgoCD pas à jour | `just argocd-sync` |
| Pas de kubeconfig | `just kubeconfig` |
| État nœuds | `just status` |
| UI locale sans tailnet | `just grafana` / `just argocd-ui` |

## Checklist jury

- [ ] `just demo` sans erreur
- [ ] Au moins une alerte ou graphique SLO visible dans Grafana
- [ ] Pod tué puis recréé (chaos-kill)
- [ ] HPA ou replicas > 1 sous charge (optionnel)
