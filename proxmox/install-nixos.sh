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

# Prepare an extra-files directory with the Tailscale auth key, if available.
EXTRA_FILES_DIR="$(mktemp -d)"
trap 'rm -rf "$EXTRA_FILES_DIR"' EXIT
if [ -s "$TS_AUTH_KEY_FILE" ]; then
  install -d -m 0700 "$EXTRA_FILES_DIR/var/lib/tailscale"
  install -m 0600 "$TS_AUTH_KEY_FILE" "$EXTRA_FILES_DIR/var/lib/tailscale/auth.key"
  EXTRA_ARGS=(--extra-files "$EXTRA_FILES_DIR")
  echo "[$(date +%T)] tailscale auth key found, will be deployed to /var/lib/tailscale/auth.key"
else
  EXTRA_ARGS=()
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
  echo "[$(date +%T)] start $host ($ip) -> $log"
  if nix run github:nix-community/nixos-anywhere --extra-experimental-features "nix-command flakes" -- \
      --ssh-option "IdentityFile=$IDENTITY_FILE" \
      --ssh-option "IdentitiesOnly=yes" \
      --ssh-option "StrictHostKeyChecking=no" \
      --ssh-option "UserKnownHostsFile=/dev/null" \
      "${EXTRA_ARGS[@]}" \
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
