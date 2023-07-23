#!/bin/bash
set -Eeuo pipefail
set -o nounset
set -o errexit

source ../common/entrypoint.sh

ISO_DIR="/test/"
VMMEM=2048
INSTALL_ISO="/vm/GRMCENEVAL_EN_DVD_amd64.iso"
VIRTIO_OS="w7"
VIRTIO_ARCH="amd64"

build_container "w7x64"
