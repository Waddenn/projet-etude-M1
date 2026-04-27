#!/usr/bin/env bash
set -euo pipefail

TEMPLATE_ID="${TEMPLATE_ID:-9000}"
TEMPLATE_NAME="${TEMPLATE_NAME:-debian-12-nixos-bootstrap}"
STORAGE="${STORAGE:-Storage}"
BRIDGE="${BRIDGE:-vmbr0}"
IMAGE_URL="${IMAGE_URL:-https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2}"
IMAGE_PATH="${IMAGE_PATH:-/var/lib/vz/template/iso/debian-12-genericcloud-amd64.qcow2}"

if qm status "$TEMPLATE_ID" >/dev/null 2>&1; then
  echo "Template VMID $TEMPLATE_ID already exists; skipping."
  exit 0
fi

mkdir -p "$(dirname "$IMAGE_PATH")"
if [ ! -f "$IMAGE_PATH" ]; then
  wget -O "$IMAGE_PATH" "$IMAGE_URL"
fi

qm create "$TEMPLATE_ID" \
  --name "$TEMPLATE_NAME" \
  --memory 2048 \
  --cores 2 \
  --cpu host \
  --net0 "virtio,bridge=$BRIDGE" \
  --ostype l26 \
  --agent enabled=1 \
  --scsihw virtio-scsi-single

qm importdisk "$TEMPLATE_ID" "$IMAGE_PATH" "$STORAGE"
qm set "$TEMPLATE_ID" --scsi0 "$STORAGE:vm-$TEMPLATE_ID-disk-0,discard=on,iothread=1"
qm set "$TEMPLATE_ID" --ide2 "$STORAGE:cloudinit"
qm set "$TEMPLATE_ID" --boot order=scsi0
qm set "$TEMPLATE_ID" --serial0 socket --vga serial0
qm template "$TEMPLATE_ID"

echo "Created Proxmox template $TEMPLATE_NAME with VMID $TEMPLATE_ID."
