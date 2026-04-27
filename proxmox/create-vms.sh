#!/usr/bin/env bash
set -euo pipefail

TEMPLATE_ID="${TEMPLATE_ID:-9000}"
STORAGE="${STORAGE:-Storage}"
SSH_KEY_FILE="${SSH_KEY_FILE:-/root/k3s-admin.pub}"
GATEWAY="${GATEWAY:-192.168.1.254}"
DNS="${DNS:-1.1.1.1}"

if [ ! -f "$SSH_KEY_FILE" ]; then
  echo "Missing SSH public key: $SSH_KEY_FILE" >&2
  exit 1
fi

create_vm() {
  local vmid="$1"
  local name="$2"
  local ip="$3"
  local cores="$4"
  local memory="$5"
  local disk_gb="$6"

  if qm status "$vmid" >/dev/null 2>&1; then
    echo "VM $vmid ($name) already exists; skipping."
    return
  fi

  qm clone "$TEMPLATE_ID" "$vmid" --name "$name" --full 1 --storage "$STORAGE"
  qm set "$vmid" \
    --cores "$cores" \
    --memory "$memory" \
    --ciuser root \
    --sshkeys "$SSH_KEY_FILE" \
    --ipconfig0 "ip=$ip/24,gw=$GATEWAY" \
    --nameserver "$DNS" \
    --agent enabled=1
  qm resize "$vmid" scsi0 "${disk_gb}G"
  qm start "$vmid"
}

create_vm 301 k3s-cp-1 192.168.1.61 2 6144 32
create_vm 302 k3s-worker-1 192.168.1.62 2 6144 32
create_vm 303 k3s-worker-2 192.168.1.63 2 6144 32

echo "K3s bootstrap VMs requested. Wait for cloud-init, then run nixos-anywhere from the project directory."
