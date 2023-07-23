FROM fedora:37 as Build

# Build dependencies
RUN dnf install -y --setopt=install_weak_deps=False --best \
    qemu-system-x86-core hostname
RUN pkg="$(dnf install -y --setopt=install_weak_deps=False --best unzip \
      p7zip-plugins gcab cpio findutils aria2 jq genisoimage qemu-img xmlstarlet)" && \
    echo "$(echo $pkg | sed 's/Installed:/\n/g' | sed -z 's/Complete!//g' | sed -n '2 p')" > /opt/pkg && \
    curl -L https://github.com/mikefarah/yq/releases/download/v4.30.6/yq_linux_amd64.tar.gz > yq_linux_amd64.tar.gz && \
    echo "5fb0cb916ded1e516cf39a7d86d5d9d55c9578b495b35f4baf5583ffde2bc29a yq_linux_amd64.tar.gz" \
    | sha256sum --check --status - && \
    tar xvf yq_linux_amd64.tar.gz && \
    rm yq_linux_amd64.tar.gz && mv yq_linux_amd64 /usr/bin/yq


# Choose which drivers to include from virtio iso
ARG CTR_VIRTIO_OS
ARG CTR_VIRTIO_ARCH

ENV VMDISK="/opt/vm.qcow2"
COPY . /
# Call the main from here to allow overriding
RUN touch /tmp/stage1 && bash -c "source /build.sh; main" && rm -rf /tmp/stage1

ENTRYPOINT ["/bin/bash", "/start.sh"]


