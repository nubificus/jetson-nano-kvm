FROM ananos/debian-dev-aarch64 as build

# Grab build dependencies
RUN apt-get --allow-releaseinfo-change update && apt install -y  build-essential libssl-dev bc flex bison libelf-dev openssl libssl-dev bc cpio rsync kmod

RUN mkdir -p /build
WORKDIR /build

# Download the L4T source tarball
#RUN wget -c https://developer.nvidia.com/embedded/dlc/r32-3-1_Release_v1.0/Sources/T186/public_sources.tbz2
RUN wget -c https://developer.nvidia.com/embedded/l4t/r32_release_v5.1/r32_release_v5.1/sources/t210/public_sources.tbz2

# Unpack the kernel tarball
RUN tar -jxpf public_sources.tbz2
RUN cd Linux_for_Tegra/source/public && tar -jxpf kernel_src.tbz2

# Get gcc-7 aarch64 toolchain
RUN mkdir -p /store/toolchains
WORKDIR /store/toolchains
RUN wget --no-check-certificate https://releases.linaro.org/components/toolchain/binaries/latest-7/aarch64-linux-gnu/gcc-linaro-7.5.0-2019.12-x86_64_aarch64-linux-gnu.tar.xz && xzcat gcc-linaro-7.5.0-2019.12-x86_64_aarch64-linux-gnu.tar.xz | tar -xf -

# Download patch and kernel config.
# If no branch is specified, then the latest L4T release is used.
RUN git clone https://github.com/cloudkernels/Xavier-KVM.git ~/Xavier-KVM -b Nano/t210-ananos
WORKDIR /root/Xavier-KVM 
RUN git pull

WORKDIR /build/Linux_for_Tegra/source/public/hardware
# Patch the device tree
#RUN patch -Np1 -i ~/Xavier-KVM/patches/hardware/0001-Enable-KVM-support-for-t194.patch
RUN patch -Np1 -i ~/Xavier-KVM/patches/hardware/0001-Enable-KVM-support-for-t210.patch

# Patch the kernel
WORKDIR /build/Linux_for_Tegra/source/public/kernel/kernel-4.9
RUN for i in ~/Xavier-KVM/patches/kernel/*; do patch -Np1 -i $i; done

# Copy the kernel config to the kernel source tree
RUN cp ~/Xavier-KVM/config-4.9.140-kvm arch/arm64/configs/tegra-kvm_defconfig
RUN touch .config
RUN make ARCH=arm64 CROSS_COMPILE=/store/toolchains/gcc-linaro-7.5.0-2019.12-x86_64_aarch64-linux-gnu/bin/aarch64-linux-gnu- tegra-kvm_defconfig

# Build kernel components
RUN make ARCH=arm64 Image -j$(nproc) CROSS_COMPILE=/store/toolchains/gcc-linaro-7.5.0-2019.12-x86_64_aarch64-linux-gnu/bin/aarch64-linux-gnu-
RUN make ARCH=arm64 dtbs -j$(nproc) CROSS_COMPILE=/store/toolchains/gcc-linaro-7.5.0-2019.12-x86_64_aarch64-linux-gnu/bin/aarch64-linux-gnu-
RUN make ARCH=arm64 modules -j$(nproc) CROSS_COMPILE=/store/toolchains/gcc-linaro-7.5.0-2019.12-x86_64_aarch64-linux-gnu/bin/aarch64-linux-gnu-

# Install kernel modules and firmware
RUN make ARCH=arm64 modules_install -j$(nproc) CROSS_COMPILE=/store/toolchains/gcc-linaro-7.5.0-2019.12-x86_64_aarch64-linux-gnu/bin/aarch64-linux-gnu-

FROM scratch as artifact
COPY --from=build /lib/modules/ /modules
COPY --from=build /lib/firmware/ /firmware
COPY --from=build /build/Linux_for_Tegra/source/public/kernel/kernel-4.9/arch/arm64/boot/Image /Image
COPY --from=build /build/Linux_for_Tegra/source/public/kernel/kernel-4.9/arch/arm64/boot/dts/tegra210-p3448-0000-p3449-0000-a02.dtb /tegra210-p3448-0000-p3449-0000-a02.dtb
COPY --from=build /build/Linux_for_Tegra/source/public/kernel/kernel-4.9/arch/arm64/boot/dts/tegra210-p3448-0000-p3449-0000-b00.dtb /tegra210-p3448-0000-p3449-0000-b00.dtb
