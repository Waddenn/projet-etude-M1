#!/usr/bin/env bash
# Bootstrap des SSH host keys persistantes par VM + alignement de .sops.yaml.
#
# Idempotent. Génère une paire ed25519 par hôte si absente,
# met à jour les recipients age dans nixos/.sops.yaml et re-encrypte
# nixos/secrets/secrets.yaml pour les recipients courants.
#
# But : casser le chicken-and-egg entre `just recreate` (nouvelles VMs =
# nouvelles SSH host keys) et sops-nix (recipients hardcodés). On utilise
# des host keys *persistantes côté dev* qu'on injecte via nixos-anywhere
# `--extra-files`. Les VMs ont donc toujours les mêmes clés et donc les
# mêmes age recipients.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SECRETS_DIR="${SECRETS_DIR:-$ROOT_DIR/secrets}"
HOST_KEYS_DIR="$SECRETS_DIR/host-keys"
SOPS_YAML="$ROOT_DIR/nixos/.sops.yaml"
SECRETS_FILE="$ROOT_DIR/nixos/secrets/secrets.yaml"

HOSTS=("k3s-cp-1" "k3s-worker-1" "k3s-worker-2")

# Auto-élévation dans le devShell si l'un des outils manque.
if ! command -v ssh-to-age >/dev/null 2>&1 || ! command -v sops >/dev/null 2>&1 || ! command -v yq >/dev/null 2>&1; then
  if [ -z "${BOOTSTRAP_HOST_KEYS_REENTERED:-}" ]; then
    export BOOTSTRAP_HOST_KEYS_REENTERED=1
    exec nix --extra-experimental-features "nix-command flakes" develop "$ROOT_DIR/nixos" -c "$SCRIPT_DIR/$(basename "$0")" "$@"
  fi
  echo "missing tool after nix develop entry — abort" >&2
  exit 1
fi

mkdir -p "$HOST_KEYS_DIR"

# 1. Génère les paires ed25519 manquantes.
for host in "${HOSTS[@]}"; do
  hdir="$HOST_KEYS_DIR/$host"
  key="$hdir/ssh_host_ed25519_key"
  if [ ! -s "$key" ]; then
    install -d -m 0700 "$hdir"
    ssh-keygen -t ed25519 -N "" -C "$host" -f "$key" >/dev/null
    chmod 0600 "$key"
    chmod 0644 "$key.pub"
    echo "[host-keys] généré $key"
  fi
done

# 2. Calcule l'age pubkey de chaque host à partir de la pubkey ssh.
declare -A AGE_PUB
for host in "${HOSTS[@]}"; do
  pub="$HOST_KEYS_DIR/$host/ssh_host_ed25519_key.pub"
  AGE_PUB[$host]=$(ssh-to-age <"$pub")
done

# 3. Aligne nixos/.sops.yaml avec ces age recipients.
#    On remplace en place via yq pour préserver le reste du fichier.
TMP_SOPS=$(mktemp)
cp "$SOPS_YAML" "$TMP_SOPS"

# Remplace chaque ancre &k3s_* par la nouvelle valeur. yq ne supporte pas
# bien les ancres en édition ; on utilise une sub sed sur la ligne d'ancre.
update_anchor() {
  local anchor="$1"
  local newval="$2"
  # Ligne de la forme: "  - &<anchor>  age1..."
  if grep -Eq "^[[:space:]]*-[[:space:]]+&${anchor}[[:space:]]+age1[a-z0-9]+" "$TMP_SOPS"; then
    sed -i -E "s|^([[:space:]]*-[[:space:]]+&${anchor}[[:space:]]+)age1[a-z0-9]+|\1${newval}|" "$TMP_SOPS"
  else
    echo "[sops] anchor &${anchor} introuvable dans $SOPS_YAML" >&2
    exit 1
  fi
}

update_anchor "k3s_cp_1"     "${AGE_PUB[k3s-cp-1]}"
update_anchor "k3s_worker_1" "${AGE_PUB[k3s-worker-1]}"
update_anchor "k3s_worker_2" "${AGE_PUB[k3s-worker-2]}"

if ! cmp -s "$TMP_SOPS" "$SOPS_YAML"; then
  mv "$TMP_SOPS" "$SOPS_YAML"
  echo "[sops] $SOPS_YAML mis à jour avec les age keys courantes"
else
  rm -f "$TMP_SOPS"
fi

# 4. Re-encrypte secrets.yaml pour les recipients courants.
#    `sops updatekeys` est idempotent : ne fait rien si déjà aligné.
if [ -f "$SECRETS_FILE" ]; then
  ( cd "$ROOT_DIR/nixos" && sops updatekeys -y "secrets/secrets.yaml" )
fi

echo "[bootstrap] OK — host keys persistées dans $HOST_KEYS_DIR"
