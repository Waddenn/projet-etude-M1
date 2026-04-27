# Tâches de gestion du cluster k3s/Proxmox.
# Lister les recettes : `just`
# Lancer une recette  : `just <nom>`

set shell := ["bash", "-cu"]
set dotenv-load := true

secrets  := env_var_or_default("SECRETS_DIR", justfile_directory() + "/secrets")
key      := env_var_or_default("PROJET_K3S_KEY", secrets + "/ssh-deploy-key")
ts_key   := env_var_or_default("TS_AUTH_KEY_FILE", secrets + "/tailscale-authkey")
kubecfg  := env_var_or_default("KUBECONFIG", env_var("HOME") + "/.kube/projet-etude")
ssh_opts := "-i " + key + " -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5"

cp_ip := "192.168.1.61"
w1_ip := "192.168.1.62"
w2_ip := "192.168.1.63"

# Affiche les recettes disponibles
default:
    @just --list

# ---------- SSH ----------

# SSH vers le control-plane (LAN)
cp:
    ssh {{ssh_opts}} ops@{{cp_ip}}

# SSH vers worker-1 (LAN)
w1:
    ssh {{ssh_opts}} ops@{{w1_ip}}

# SSH vers worker-2 (LAN)
w2:
    ssh {{ssh_opts}} ops@{{w2_ip}}

# SSH vers le Proxmox host
pve:
    ssh root@proxade

# Liste les VMs Proxmox
pve-list:
    ssh root@proxade qm list

# ---------- Déploiement ----------

# Pré-requis: clé tailscale dans {{ts_key}}, clé SSH dans {{key}}.
# Déploie les 3 nœuds en parallèle via nixos-anywhere (recréation propre)
deploy:
    distrobox enter nix-deploy -- bash -lc 'cd {{justfile_directory()}} && ./proxmox/install-nixos.sh'

# Recrée les 3 VMs sur Proxmox depuis le template
recreate:
    ssh root@proxade 'for vm in 301 302 303; do qm stop $vm 2>/dev/null; sleep 1; qm destroy $vm --purge 1 2>/dev/null || true; done'
    ssh root@proxade bash -s < {{justfile_directory()}}/proxmox/create-vms.sh

# Reconstruit + active la config NixOS sur les nœuds existants (pas de recréation)
switch:
    distrobox enter nix-deploy -- bash -lc 'cd {{justfile_directory()}} && ./proxmox/switch-nixos.sh'

# Pipeline complet: destroy -> recreate -> deploy
redeploy: recreate wait-ssh deploy

# Attend que SSH réponde sur les 3 nœuds
wait-ssh:
    @echo "Attente SSH sur les 3 nœuds..."
    @until for ip in {{cp_ip}} {{w1_ip}} {{w2_ip}}; do timeout 3 bash -c "</dev/tcp/$ip/22" 2>/dev/null || exit 1; done; do sleep 5; done
    @echo "OK"

# ---------- Diagnostic ----------

# Ping rapide des 3 nœuds
ping:
    @for ip in {{cp_ip}} {{w1_ip}} {{w2_ip}}; do printf "%s: " "$ip"; ping -c 1 -W 2 "$ip" >/dev/null 2>&1 && echo OK || echo FAIL; done

# État rapide: hostname, k3s actif, IP tailscale
status:
    @for ip in {{cp_ip}} {{w1_ip}} {{w2_ip}}; do \
        echo "=== $ip ==="; \
        ssh {{ssh_opts}} ops@$ip 'hostname; systemctl is-active k3s 2>/dev/null || systemctl is-active k3s-agent 2>/dev/null; sudo tailscale ip -4 2>/dev/null' 2>&1 | tail -5; \
    done

# Tail des logs nixos-anywhere
logs:
    @ls -la /tmp/nixos-anywhere-logs/ 2>/dev/null
    @echo "--- launcher ---"
    @tail -20 /tmp/nixos-anywhere-launcher.log 2>/dev/null

# Suit en live les logs de déploiement
logs-follow:
    tail -f /tmp/nixos-anywhere-launcher.log /tmp/nixos-anywhere-logs/*.log

# ---------- Kubernetes ----------

# Récupère le kubeconfig depuis cp-1 et l'écrit dans {{kubecfg}}
kubeconfig:
    @mkdir -p $(dirname {{kubecfg}})
    @ssh {{ssh_opts}} ops@{{cp_ip}} 'sudo cat /etc/rancher/k3s/k3s.yaml' \
        | sed 's|127\.0\.0\.1|{{cp_ip}}|' > {{kubecfg}}
    @chmod 600 {{kubecfg}}
    @echo "kubeconfig écrit dans {{kubecfg}}"
    @echo "export KUBECONFIG={{kubecfg}}"

# Liste les nodes du cluster
nodes:
    KUBECONFIG={{kubecfg}} kubectl get nodes -o wide

# Liste tous les pods
pods:
    KUBECONFIG={{kubecfg}} kubectl get pods -A

# kubectl proxy avec ce kubeconfig (passe les args: just k get nodes)
k *args:
    KUBECONFIG={{kubecfg}} kubectl {{args}}

# ---------- Tailscale ----------

# Vérifie l'état tailscale sur les 3 nœuds
ts-status:
    @for ip in {{cp_ip}} {{w1_ip}} {{w2_ip}}; do \
        echo "=== $ip ==="; \
        ssh {{ssh_opts}} ops@$ip 'sudo tailscale status 2>&1 | head -3; sudo tailscale ip -4' 2>&1 | tail -5; \
    done

# ---------- ArgoCD / GitOps ----------

# (Le bootstrap ArgoCD est désormais déclaratif via le module NixOS
#  `modules/k8s-bootstrap.nix`. Plus de recette `argocd-bootstrap`.)

# Mot de passe admin initial d'ArgoCD
argocd-password:
    @KUBECONFIG={{kubecfg}} kubectl -n argocd get secret argocd-initial-admin-secret \
        -o jsonpath='{.data.password}' | base64 -d; echo

# Port-forward de l'UI ArgoCD sur https://localhost:8080
argocd-ui:
    @echo "ArgoCD UI: https://localhost:8080  (user: admin)"
    KUBECONFIG={{kubecfg}} kubectl -n argocd port-forward svc/argocd-server 8080:443

# Force la synchro de la root app (utile après un push git récent)
argocd-sync:
    KUBECONFIG={{kubecfg}} kubectl -n argocd patch app root --type merge \
        -p '{"operation":{"sync":{"revision":"HEAD"}}}'

# Liste les Applications ArgoCD avec leur état
argocd-apps:
    KUBECONFIG={{kubecfg}} kubectl -n argocd get applications -o wide

# ---------- Monitoring ----------

# Port-forward de Grafana sur http://localhost:3000  (user: admin / pwd: admin)
grafana:
    @echo "Grafana: http://localhost:3000  (admin / admin)"
    KUBECONFIG={{kubecfg}} kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80

# Port-forward de Prometheus sur http://localhost:9090
prometheus:
    KUBECONFIG={{kubecfg}} kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090

# État des pods monitoring
mon-status:
    KUBECONFIG={{kubecfg}} kubectl -n monitoring get pods,svc,pvc

# ---------- Secrets (sops-nix) ----------

# Génère une age key dev locale (~/.config/sops/age/keys.txt) si absente
sops-init:
    @mkdir -p $HOME/.config/sops/age
    @if [ ! -f $HOME/.config/sops/age/keys.txt ]; then \
        age-keygen -o $HOME/.config/sops/age/keys.txt; \
        echo; echo "Public key (à coller dans nixos/.sops.yaml):"; \
        grep '^# public key:' $HOME/.config/sops/age/keys.txt | sed 's/^# public key: //'; \
    else \
        echo "age key déjà présente:"; \
        grep '^# public key:' $HOME/.config/sops/age/keys.txt; \
    fi

# Édite le fichier secrets encrypté
sops-edit:
    cd {{justfile_directory()}}/nixos && sops secrets/secrets.yaml

# Affiche la clé age dérivée de la clé SSH host de chaque VM
sops-host-keys:
    @for ip in {{cp_ip}} {{w1_ip}} {{w2_ip}}; do \
        printf "%s: " "$ip"; \
        ssh-keyscan -t ed25519 "$ip" 2>/dev/null | ssh-to-age 2>/dev/null || echo "(unreachable)"; \
    done

# Re-encrypte secrets.yaml en intégrant les recipients courants de .sops.yaml
sops-rotate:
    cd {{justfile_directory()}}/nixos && sops updatekeys -y secrets/secrets.yaml
