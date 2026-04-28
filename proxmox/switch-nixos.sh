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

if ! command -v nixos-rebuild >/dev/null 2>&1; then
  echo "nixos-rebuild is required locally. Run from NixOS or install nixos-rebuild in your Nix profile." >&2
  exit 1
fi

if [ ! -f "$IDENTITY_FILE" ]; then
  echo "Missing SSH private key: $IDENTITY_FILE" >&2
  exit 1
fi

TS_AUTH_KEY_FILE="${TS_AUTH_KEY_FILE:-$SECRETS_DIR/tailscale-authkey}"

export NIX_SSHOPTS="-F /dev/null -i $IDENTITY_FILE -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
export NIX_CONFIG="${NIX_CONFIG:-experimental-features = nix-command flakes}"

push_tailscale_key() {
  local target_ip="$1"
  if [ ! -s "$TS_AUTH_KEY_FILE" ]; then
    return 0
  fi
  # shellcheck disable=SC2086 # NIX_SSHOPTS doit être word-splitted (multi-flags ssh)
  ssh $NIX_SSHOPTS "ops@$target_ip" \
    'sudo install -d -m 0700 /var/lib/tailscale && sudo install -m 0600 /dev/stdin /var/lib/tailscale/auth.key' \
    < "$TS_AUTH_KEY_FILE"
}

push_tailscale_key 192.168.1.61
push_tailscale_key 192.168.1.62
push_tailscale_key 192.168.1.63

nixos-rebuild switch --flake .#k3s-cp-1 --target-host ops@192.168.1.61 --use-remote-sudo
nixos-rebuild switch --flake .#k3s-worker-1 --target-host ops@192.168.1.62 --use-remote-sudo
nixos-rebuild switch --flake .#k3s-worker-2 --target-host ops@192.168.1.63 --use-remote-sudo
