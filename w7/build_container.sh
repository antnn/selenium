#!/bin/bash
set -Eeuo pipefail
set -o nounset
set -o errexit

source ../common/entrypoint.sh
parentdir=$(dirname `pwd`)
_ISO="7600.16385.090713-1255_x86fre_enterprise_en-us_EVAL_Eval_Enterprise-GRMCENEVAL_EN_DVD.iso"
export VMMEM=2048
export VM_DISK_SIZE=30G
export INSTALL_ISO="${parentdir}/iso/${_ISO}"
export VIRTIO_OS="w7"
export VIRTIO_ARCH="x86"

build_container "w7"
