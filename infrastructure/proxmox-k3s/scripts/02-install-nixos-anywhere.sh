#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SECRETS_DIR="${SECRETS_DIR:-$SCRIPT_DIR/../secrets}"
IDENTITY_FILE="${IDENTITY_FILE:-$SECRETS_DIR/ssh-deploy-key}"

cd "$SCRIPT_DIR/../nixos"

if [ -f "$HOME/.nix-profile/etc/profile.d/nix.sh" ]; then
  # Needed when the script runs from a fresh Distrobox shell.
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

export NIX_SSHOPTS="-F /dev/null -i $IDENTITY_FILE -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
export NIX_CONFIG="${NIX_CONFIG:-experimental-features = nix-command flakes}"

deploy_node() {
  local host="$1"
  local ip="$2"

  nix run github:nix-community/nixos-anywhere --extra-experimental-features "nix-command flakes" -- \
    --ssh-option "IdentityFile=$IDENTITY_FILE" \
    --ssh-option "IdentitiesOnly=yes" \
    --ssh-option "StrictHostKeyChecking=no" \
    --ssh-option "UserKnownHostsFile=/dev/null" \
    --flake ".#$host" \
    "root@$ip"
}

deploy_node k3s-cp-1 192.168.1.61
deploy_node k3s-worker-1 192.168.1.62
deploy_node k3s-worker-2 192.168.1.63
