#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SECRETS_DIR="${SECRETS_DIR:-$SCRIPT_DIR/../secrets}"
IDENTITY_FILE="${IDENTITY_FILE:-$SECRETS_DIR/ssh-deploy-key}"
TS_AUTH_KEY_FILE="${TS_AUTH_KEY_FILE:-$SECRETS_DIR/tailscale-authkey}"

cd "$SCRIPT_DIR/../nixos"
LOG_DIR="${LOG_DIR:-/tmp/nixos-anywhere-logs}"

if [ -f "$HOME/.nix-profile/etc/profile.d/nix.sh" ]; then
  # shellcheck disable=SC1091
  . "$HOME/.nix-profile/etc/profile.d/nix.sh"
fi

if ! command -v nix >/dev/null 2>&1; then
  echo "nix is required locally. Install Nix first: https://nixos.org/download/" >&2
  exit 1
fi

if [ ! -f "$IDENTITY_FILE" ]; then
  echo "Missing SSH private key: $IDENTITY_FILE" >&2
  exit 1
fi

mkdir -p "$LOG_DIR"

# 0. Bootstrap des SSH host keys persistantes + alignement sops.
#    Idempotent : sans effet si déjà à jour.
"$SCRIPT_DIR/bootstrap-host-keys.sh"

HOST_KEYS_DIR="${HOST_KEYS_DIR:-$SECRETS_DIR/host-keys}"

# Prepare a per-host extra-files directory.
# - Tailscale auth key (commun aux 3 hôtes, si présente)
# - SSH host key persistante (spécifique par hôte) → permet à sops-nix
#   de déchiffrer les secrets dès la première activation, même sur VM neuve.
EXTRA_FILES_ROOT="$(mktemp -d)"
trap 'rm -rf "$EXTRA_FILES_ROOT"' EXIT

build_extra_files() {
  local host="$1"
  local dir="$EXTRA_FILES_ROOT/$host"
  install -d -m 0755 "$dir"
  if [ -s "$TS_AUTH_KEY_FILE" ]; then
    install -d -m 0700 "$dir/var/lib/tailscale"
    install -m 0600 "$TS_AUTH_KEY_FILE" "$dir/var/lib/tailscale/auth.key"
  fi
  local hk="$HOST_KEYS_DIR/$host/ssh_host_ed25519_key"
  if [ ! -s "$hk" ]; then
    echo "missing host key: $hk (run proxmox/bootstrap-host-keys.sh)" >&2
    exit 1
  fi
  install -d -m 0755 "$dir/etc/ssh"
  install -m 0600 "$hk"     "$dir/etc/ssh/ssh_host_ed25519_key"
  install -m 0644 "$hk.pub" "$dir/etc/ssh/ssh_host_ed25519_key.pub"
  echo "$dir"
}

if [ -s "$TS_AUTH_KEY_FILE" ]; then
  echo "[$(date +%T)] tailscale auth key found, will be deployed to /var/lib/tailscale/auth.key"
else
  echo "[$(date +%T)] no tailscale auth key at $TS_AUTH_KEY_FILE — nodes will need 'tailscale up' manually"
fi

export NIX_SSHOPTS="-F /dev/null -i $IDENTITY_FILE -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
export NIX_CONFIG="${NIX_CONFIG:-experimental-features = nix-command flakes}"

# Pre-build the three closures once so the SSH-copy phases don't fight over evaluation.
echo "[$(date +%T)] pre-building closures locally..."
nix build --extra-experimental-features "nix-command flakes" --no-link --print-out-paths \
  ".#nixosConfigurations.k3s-cp-1.config.system.build.toplevel" \
  ".#nixosConfigurations.k3s-worker-1.config.system.build.toplevel" \
  ".#nixosConfigurations.k3s-worker-2.config.system.build.toplevel"
echo "[$(date +%T)] closures built."

deploy_node() {
  local host="$1"
  local ip="$2"
  local log="$LOG_DIR/$host.log"
  local extra_dir
  extra_dir="$(build_extra_files "$host")"
  echo "[$(date +%T)] start $host ($ip) -> $log"
  if nix run github:nix-community/nixos-anywhere --extra-experimental-features "nix-command flakes" -- \
      --ssh-option "IdentityFile=$IDENTITY_FILE" \
      --ssh-option "IdentitiesOnly=yes" \
      --ssh-option "StrictHostKeyChecking=no" \
      --ssh-option "UserKnownHostsFile=/dev/null" \
      --extra-files "$extra_dir" \
      --flake ".#$host" \
      "root@$ip" >"$log" 2>&1; then
    echo "[$(date +%T)] OK   $host"
  else
    echo "[$(date +%T)] FAIL $host (see $log)" >&2
    return 1
  fi
}

deploy_node k3s-cp-1     192.168.1.61 &
PID_CP=$!
deploy_node k3s-worker-1 192.168.1.62 &
PID_W1=$!
deploy_node k3s-worker-2 192.168.1.63 &
PID_W2=$!

wait "$PID_CP" && RC0=0 || RC0=$?
wait "$PID_W1" && RC1=0 || RC1=$?
wait "$PID_W2" && RC2=0 || RC2=$?

if [ "$RC0" -ne 0 ] || [ "$RC1" -ne 0 ] || [ "$RC2" -ne 0 ]; then
  echo "Deployment failed (cp=$RC0 w1=$RC1 w2=$RC2). Logs in $LOG_DIR" >&2
  exit 1
fi
echo "All nodes deployed."
