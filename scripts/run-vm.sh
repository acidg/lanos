#!/usr/bin/env bash
# Boot the built image in QEMU, attached as a USB stick to a UEFI machine.
#
# Writes go to a copy-on-write overlay in vm/, so the image itself stays untouched and
# the overlay keeps state between runs. Delete vm/ (or rebuild the image) to test a
# fresh first boot again.
#
# Environment:
#   VM_IMAGE     raw image to boot (default result-image/lanos.img), e.g. a copy
#                prepared with add-ssh-key.sh
#   STICK_SIZE   size of the virtual stick (default 64G)
#   VM_DISPLAY   QEMU display (default gtk, e.g. "none")
#   VM_SSH_PORT  host port forwarded to the stick's SSH port (default 2222)
# Extra arguments are passed to QEMU.
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
image=$(realpath "${VM_IMAGE:-$repo/result-image/lanos.img}")
vm="$repo/vm"
overlay="$vm/stick.qcow2"

pkg() { nix build --inputs-from "$repo" --no-link --print-out-paths "nixpkgs#$1"; }
qemu=$(pkg qemu_kvm)/bin
ovmf=$(pkg OVMF.fd)/FV

mkdir -p "$vm"
if [[ -f $overlay ]] && ! "$qemu/qemu-img" info "$overlay" | grep -qF "backing file: $image"; then
  echo "Image changed, starting from a fresh overlay."
  rm -f "$overlay" "$vm/OVMF_VARS.fd"
fi
[[ -f $overlay ]] || "$qemu/qemu-img" create -q -f qcow2 -F raw -b "$image" "$overlay" "${STICK_SIZE:-64G}"
[[ -f $vm/OVMF_VARS.fd ]] || install -m 644 "$ovmf/OVMF_VARS.fd" "$vm/"

exec "$qemu/qemu-system-x86_64" \
  -enable-kvm -machine q35 -cpu host -smp 4 -m 4096 \
  -drive if=pflash,format=raw,readonly=on,file="$ovmf/OVMF_CODE.fd" \
  -drive if=pflash,format=raw,file="$vm/OVMF_VARS.fd" \
  -device qemu-xhci \
  -drive if=none,id=stick,format=qcow2,file="$overlay" \
  -device usb-storage,drive=stick \
  -device virtio-vga \
  -display "${VM_DISPLAY:-gtk}" \
  -monitor unix:"$vm/monitor.sock",server,nowait \
  -nic user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:"${VM_SSH_PORT:-2222}"-:22 \
  "$@"
