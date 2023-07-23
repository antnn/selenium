#!/bin/bash
# May be overridden by build.override.sh
export USER=root
set -Eeuo pipefail
set -o nounset
set -o errexit

declare INSTALL_ISO
export CONFIG_DIR="/config_iso"
export CONFIG_ISO="/opt/config.iso"
export DRIVERS_DIR="/config_iso/\$WinpeDriver\$"
export DOWNLOAD_DIR="/config_iso/toinstall"
export INSTALL_LIST="/config_iso/install.json"
export NPROC=1

NPROC=$(nproc)
yq -o=json config_iso/install.yml >$INSTALL_LIST
INSTALL_LIST="$(<"${INSTALL_LIST}")"
#NOTE: Need to split to 2 stages to run with kvm device
stage1() {
  printf "%s [\e[94m INFO \e[0m] Build stage: 1\n" "$(d)"
  download_files
  #extract_sp1
  #fix_sp1_offline_install
  extract_virtio_drivers
  printf "%s [\e[94m INFO \e[0m] Making configuration iso: \e[94m%s \e[0m\n" "$(d)" "$CONFIG_ISO"
  mkisofs -joliet-long -l -J -r -V 'CONFIG_ISO' -o "$CONFIG_ISO" "$CONFIG_DIR"
  exit
}

main() {
  if [ -f /tmp/stage1 ]; then
    stage1
  fi
  printf "%s [\e[94m INFO \e[0m] Build stage: 2\n" "$(d)"
  if [ ! -f "$INSTALL_ISO" ]; then
    printf "%s [\e[31m ERROR \e[0m] Windows installation iso not found: \e[94m%s \e[0m %s\n" "$(d)" "$INSTALL_ISO"
    exit 127
  fi
  if [ ! -e /dev/kvm ]; then
    printf "%s [\e[38;5;220m WARN \e[0m] Container needs KVM to run faster\n" "$(d)"
  fi
  qemu-img create -f qcow2 -o compression_type=zstd "$VMDISK" $CTR_VM_DISK_SIZE
  printf "%s [\e[94m INFO \e[0m] Running Windows setup \n" "$(d)"
  printf "Windows PE installation logs are at:\n\t\e[94m F:\\\$WINDOWS.~BT\\Sources\\Panther\\cbs_unattend.log \e[0m\n"
  qemu-system-x86_64 \
    -enable-kvm -smp $NPROC -cpu host -pidfile /tmp/guest.pid \
    -drive file="$VMDISK",if=virtio \
    -net nic,model=virtio-net-pci -net user,hostfwd=tcp::3389-:3389 \
    -m $VMMEM -usb -device usb-ehci,id=ehci -device usb-tablet \
    -cdrom "$INSTALL_ISO" \
    -drive file="$CONFIG_ISO",index=1,media=cdrom -vnc unix:/tmp/vnc/vnc
  #-smbios type=1,serial="" \
  #-net user,hostfwd=tcp::2222-:22,hostfwd=tcp::3389-:3389,hostfwd=tcp::$P-:$P \

  printf "%s [\e[94m INFO \e[0m] Cleaning container image: removing unnecessary packages\n" "$(d)"
  rm -f /etc/dnf/protected.d/systemd.conf
  _remove_list="$(</opt/pkg)"
  dnf remove -y --skip-broken $_remove_list
  dnf install -y --setopt=install_weak_deps=False --best hostname qemu-system-x86-core
  dnf clean all
  rm -rf "${DOWNLOAD_DIR}" "$CONFIG_ISO"
  printf "%s [\e[32m OK \e[0m] VM Image is ready. Waiting for copying running container\n" "$(d)"
  touch /opt/container_is_built
  # Wait for creating container image from current one
  while true; do
    sleep 100000000
  done
}

d() {
  date "+%m/%d %T"
}

download_files() {
  printf "%s [\e[94m INFO \e[0m] Downloading installation files from: \e[94m%s\e[0m to \e[94m%s\n\e[0m" "$(d)" "${CONFIG_DIR}/install.json" "${DOWNLOAD_DIR}"
  (
    local list=()
    mkdir -p "${DOWNLOAD_DIR}"
    cd "${DOWNLOAD_DIR}"
    __download() {
      local row
      local url
      local name
      local sum
      local i=0
      # TODO refactor to separate function which accepts name of function and the max number of parrallel jobs
      for row in $(echo "${INSTALL_LIST}" | jq -r '.[] | @base64'); do
        _jq() {
          echo ${row} | base64 --decode | jq -r ${1}
        }
        url=$(_jq '.url')
        name=$(_jq '.name')
        sum=$(_jq '.sum')
        if [[ $url != "null" ]]; then
          list+=("${name}.sha256")
          printf "%s %s" "${sum}" "${name}" >"${name}.sha256"
          local par=$NPROC
          if [[ $NPROC -gt 16 ]]; then
            par=16
          fi
          # aria2c supports up to 16
          aria2c -s${par} -x${par} "$url" -o"$name" &
          i=$((i + 1))
          # wait for the current jobs to be finished
          if [[ $i -gt $NPROC ]]; then
            wait $(jobs -p)
            i=0
          fi
        fi
      done
      wait $(jobs -p)
    }
    __download
    printf "%s [\e[94m INFO \e[0m] Checking integrity of downloaded files\n" "$(d)"
    for item in "${list[@]}"; do
      sha256sum -c "$item"
    done
  )
}

extract_virtio_drivers() {
  printf "%s [\e[94m INFO \e[0m] Extracting virtIO divers and copying to: \e[94m%s \e[0m\n" "$(d)" ${DRIVERS_DIR}
  mkdir -p "$DRIVERS_DIR"
  mkdir -p /tmp/drv
  cd /tmp/drv
  7z x "${DOWNLOAD_DIR}/virtio-win.iso"
  # FILES=$(find . -type f -follow -print | sed 's|^./||')
  # k=0
  # for f in $FILES; do
  #  cp "$f" "$DRIVERS_DIR/${k}$(basename "$f")"
  #  k=$((k + 1))
  # done
  cp -rf "vioscsi/${CTR_VIRTIO_OS}/${CTR_VIRTIO_ARCH}"/ "$DRIVERS_DIR"
  cp -rf "viostor/${CTR_VIRTIO_OS}/${CTR_VIRTIO_ARCH}/" "$DRIVERS_DIR"
  cp -rf "NetKVM/${CTR_VIRTIO_OS}/${CTR_VIRTIO_ARCH}/" "$DRIVERS_DIR"
  rm -rf /tmp/drv "${DOWNLOAD_DIR}/virtio-win.iso"
  cd /
}

edit_xml() {
  # Example of generated XML
  # <servicing>
  #   <package action="install">
  #     <assemblyIdentity name="Package_for_KB976902" version="6.1.1.17514" processorArchitecture="x86" publicKeyToken="31bf3856ad364e35" language="neutral" />
  #     <source location="D:\toinstall\01_KB976902-x86.cab" />
  #   </package>
  # </servicing>
  local output="$6"
  local pkgname="$1"
  local location="$2"
  local version="$3"
  local arch="$4" #"amd64"
  local lang="$5" #"neutral"
  local base="//x:unattend/servicing/package"
  xmlstarlet ed -N x="urn:schemas-microsoft-com:unattend" -s //x:unattend --type elem -n "servicing" \
    -s //x:unattend/servicing --type elem -n "package" \
    -s $base --type attr -n action -v "install" \
    -s $base --type elem -n assemblyIdentity \
    -s $base/assemblyIdentity --type attr -n "name" -v "$pkgname" \
    -s $base/assemblyIdentity --type attr -n "version" -v "$version" \
    -s $base/assemblyIdentity --type attr -n "processorArchitecture" -v "$arch" \
    -s $base/assemblyIdentity --type attr -n "publicKeyToken" -v "31bf3856ad364e35" \
    -s $base/assemblyIdentity --type attr -n "language" -v "$lang" \
    -s $base --type elem -n "source" \
    -s $base/source --type attr -n "location" -v "$location" "$output"
}

#--------------------------------------------------------------------------------
#DOES NOT WORK, installation fails

# Spinstall ignores /norestart key
# See https://social.technet.microsoft.com/Forums/ie/en-US/c4b7c3fc-037c-4e45-ab11-f6f64837521a/how-to-disable-reboot-after-sp1-installation-distribution-as-exe-via-sccm?forum=w7itproinstall
# Extract and install with DISM
extract_sp1_win7_x86() {
  trap 'echo  "RETURNED: $?"' PIPE
  printf "[\e[94mINFO\e[0m] Extracting SP1 from executable SfxStub\n"
  7z x "${DOWNLOAD_DIR}/sp1-x86.exe" -o/tmp/sp1
  tail -c+559166868 "/tmp/sp1/[0]" | head -c4531728 >"${DOWNLOAD_DIR}/01_KB976902-x86.cab"
  # Somehow it always fails with pipefail 129, ($C_ENGINE version 20.10.14, build a224086, OS: F35):
  #     tail -c+18165610 "/tmp/sp1/[0]" | head -c541001258 > "${DOWNLOAD_DIR}/02_KB976932-x86.cab"
  # Had to rewrite (without | ) and it does not fail:
  tail -c+18165610 "/tmp/sp1/[0]" >/tmp/sp1/1
  head -c541001258 /tmp/sp1/1 >"${DOWNLOAD_DIR}/02_KB976932-x86.cab"
  rm -rf /tmp/sp1 "${DOWNLOAD_DIR}/sp1-x86.exe"
}

fix_sp1_offline_install() {
  printf "[\e[94mINFO\e[0m] Fixing SP1 offline installation\n"
  7z x "${DOWNLOAD_DIR}/02_KB976932-x86.cab" -o/tmp/sp1
  (
    cd /tmp/sp1
    7z x -y ./*.cab
    7z x -y NestedMPPContent.cab
    #rm -rf KB976933-LangsCab*.cab NestedMPPContent.cab cabinet.cablist.ini old_cabinet.cablist.ini
    sed -i 's/targetState="Absent"/targetState="Installed"/g' "update.ses"
    sed -i 's/allowedOffline="false"/allowedOffline="true"/g' "update.mum"
    sed -i 's/allowedOffline="false"/allowedOffline="true"/g' "Windows7SP1-KB976933~31bf3856ad364e35~x86~~6.1.1.17514.mum"

    printf "[\e[94mINFO\e[0m] Packing SP1 to cabinet archive\n"
    gcab -cz "${DOWNLOAD_DIR}/02_KB976932-x86.cab" *
    rm -rf /tmp/sp1
  )
}
