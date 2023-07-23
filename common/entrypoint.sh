#!/bin/bash

set -Eeuo pipefail
set -o nounset
set -o errexit
shopt -s extglob

declare C_ENGINE
declare VMMEM
declare VM_DISK_SIZE
declare INSTALL_ISO
declare VIRTIO_OS
declare VIRTIO_ARCH

trap clean_up ERR
trap clean_up EXIT
export _CLEANED=1
#
# MAIN ENTRYPOINT of scripts
#
BUILD_DIR="build"
export tag=""
build_container() {
  check_container_engine
  tag="$1"

  mkdir -p "${BUILD_DIR}"
  # Copy from work dir excluding current builddir
  cp -r !($BUILD_DIR|build_container.sh) "${BUILD_DIR}/"
  # Copy common parts excluding entrypoint.sh
  cp -r ../common/!(entrypoint.sh) "${BUILD_DIR}/"
  (
    if [ -f build.override.sh ]; then
      printf "%s [\e[94m INFO \e[0m] Using build.override.sh\n" "$(d)"
    fi
    cd "${BUILD_DIR}"
    # Contecanate build scripts to allow reuse and overriding
    mv build.sh build.sh.part
    cat build.sh.part build.override.sh >build.sh && rm -f build.sh.part

    # NOTE: virtio-0.1.173-2 is the last working guest tools for windows 7
    $C_ENGINE build --build-arg "CTR_VIRTIO_OS=${VIRTIO_OS}" \
      --build-arg "CTR_VIRTIO_ARCH=${VIRTIO_ARCH}" \
      -t "modernie:${tag}" .

    # NOTE: Need to split to 2 stages to run with kvm device, :z (SELinux)
    # sudo mkdir /tmp/vnc; sudo chown $USER /tmp/vnc
    # sudo chcon -t container_file_t  -R   /tmp/vnc
    $C_ENGINE container create -it --name "moderniebuild${tag}" --rm \
      -e "VMMEM=${VMMEM}" \
      -e "INSTALL_ISO=${INSTALL_ISO}" \
      -e "CTR_VM_DISK_SIZE=${VM_DISK_SIZE}" \
      --device=/dev/kvm \
      --mount=type=bind,target="/tmp/vnc",z  \
      --mount=type=bind,target="${INSTALL_ISO}",z "modernie:${tag}"
    (
      trap - ERR
      trap - EXIT
      while true; do
        # Wait and check in backgound process if container reported it's ready
        set +e
        $C_ENGINE container cp "moderniebuild${tag}:/opt/container_is_built" "$PWD" >/dev/null 2>&1
        if [[ $? == 0 ]]; then
          set -e
          break
        fi
        sleep 10
      done 
      $C_ENGINE container commit "moderniebuild${tag}" "modernie:${tag}"
      # stop container here to continue
      $C_ENGINE container kill "moderniebuild${tag}"
      exit 0
    ) &
    $C_ENGINE container start -a "moderniebuild${tag}" # blocks execution until container is stopped
    exit 0
  )
  clean_up
}

d() {
  date "+%m/%d %T"
}

check_container_engine() {
  if [ -z "$C_ENGINE" ]; then
    printf "%s [\e[31m ERROR \e[0m] C_ENGINE variable is unset\n" "$(d)"
    exit 127
  fi
}

clean_up() {
  if [ -z "$_CLEANED" ];
  then
    $C_ENGINE container kill "moderniebuild${tag}"
    _CLEANED=1
  fi 
  # runs 3 times on exits
  rm -rf "${BUILD_DIR}"
  exit 0
}
