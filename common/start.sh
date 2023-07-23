#!/bin/bash
export USER=root
set -Eeuo pipefail
set -o nounset
set -o errexit

#Continue bulding container image, stage: 2
if [[ ! -f "$VMDISK" ]]; then
  source /build.sh >> /dev/null
  main
  exit
fi

d() {
  date "+%m/%d %T"
}
if [ ! -e /dev/kvm ]; then
  printf "%s [\e[38;5;220m WARN \e[0m] Container needs KVM to run faster\n" "$(d)"
fi

printf "%s [\e[38;5;220m WARN \e[0m] Use FQDN: e.g. selenium-hub.grid, due to buggy QEMU SLIRP\n" "$(d)"
printf "%s [\e[94mINFO\e[0m] Starting Windows VM \n" "$(d)"

S_EXT_ADDR=$(hostname -s)
SELENIUMPARAMS="${S_EXT_ADDR}_${S_PORT}_${S_HUB}"
if [[ ${#SELENIUMPARAMS} -gt 64 ]]; then
  printf "%s [\e[31m ERROR \e[0m] SELENIUMPARAMS is too big (>64):\n \t %s \n" "$(d)" "$SELENIUMPARAMS"
  exit 127
fi

qemu-system-x86_64 -smbios type=1,serial="$SELENIUMPARAMS" \
  -enable-kvm -smp $(nproc) -cpu host -pidfile /tmp/guest.pid \
  -drive file="$VMDISK",if=virtio \
  -net nic,model=virtio-net-pci \
  -net user,hostfwd=tcp::2222-:22,hostfwd=tcp::3389-:3389,hostfwd=tcp::$S_PORT-:$S_PORT \
  -m $VMMEM -usb -device usb-ehci,id=ehci -device usb-tablet \
  -snapshot -vnc unix:/tmp/vnc/vnc
