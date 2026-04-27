#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SECRETS_DIR="${SECRETS_DIR:-$SCRIPT_DIR/../secrets}"
IDENTITY_FILE="${IDENTITY_FILE:-$SECRETS_DIR/ssh-deploy-key}"

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

export NIX_SSHOPTS="-F /dev/null -i $IDENTITY_FILE -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
export NIX_CONFIG="${NIX_CONFIG:-experimental-features = nix-command flakes}"

deploy_node() {
  local host="$1"
  local ip="$2"
  local log="$LOG_DIR/$host.log"
  echo "[$(date +%T)] start $host ($ip) -> $log"
  if nix run github:nix-community/nixos-anywhere --extra-experimental-features "nix-command flakes" -- \
      --ssh-option "IdentityFile=$IDENTITY_FILE" \
      --ssh-option "IdentitiesOnly=yes" \
      --ssh-option "StrictHostKeyChecking=no" \
      --ssh-option "UserKnownHostsFile=/dev/null" \
      --flake ".#$host" \
      "root@$ip" >"$log" 2>&1; then
    echo "[$(date +%T)] OK   $host"
  else
    echo "[$(date +%T)] FAIL $host (see $log)" >&2
    return 1
  fi
}

deploy_node k3s-worker-1 192.168.1.62 &
PID_W1=$!
deploy_node k3s-worker-2 192.168.1.63 &
PID_W2=$!

wait "$PID_W1" && RC1=0 || RC1=$?
wait "$PID_W2" && RC2=0 || RC2=$?

if [ "$RC1" -ne 0 ] || [ "$RC2" -ne 0 ]; then
  echo "Worker deployment failed (rc1=$RC1 rc2=$RC2). Logs in $LOG_DIR" >&2
  exit 1
fi
echo "Both workers deployed."
