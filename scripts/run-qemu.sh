#!/bin/bash
# AGL SoDeV
Zonal Playground - QEMU Launcher
Boots Xen with dom0 + VMs + containers
set -e
set -u
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
SCRIPT_DIR="(cd"(cd "
(cd"(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="(dirname"(dirname "
(dirname"SCRIPT_DIR")"
IMAGE_DIR="${REPO_ROOT}/images"
XL_CONFIGS="${REPO_ROOT}/xl-configs"

QEMU configuration
QEMU_MEMORY="4096"
QEMU_CPUS="8"
QEMU_MACHINE="virt,gic-version=3"
QEMU_NET="user,hostfwd=tcp::8090-:8090,hostfwd=tcp::5900-:5900"
echo -e "GREEN========================================{GREEN}========================================
GREEN========================================{NC}"
echo -e "GREENAGLSoDeV−QEMULaunch{GREEN}AGL SoDeV - QEMU Launch
GREENAGLSoDeV−QEMULaunch{NC}"
echo -e "GREEN========================================{GREEN}========================================
GREEN========================================{NC}"

Check images exist
check_images() {
    echo -e "YELLOWCheckingrequiredimages...{YELLOW}Checking required images...
YELLOWCheckingrequiredimages...{NC}"

local required_files=(
    "Image"
    "agl-demo-platform-dom0.ext4"
    "xen"
    "zephyr-rt.bin"
)

for file in "${required_files[@]}"; do
    if [ ! -f "${IMAGE_DIR}/${file}" ]; then
        echo -e "${RED}ERROR: Missing ${file}. Run ./scripts/build.sh first.${NC}"
        exit 1
    fi
done

echo -e "${GREEN}✓ All images present${NC}"
}
Create device tree for Xen boot
create_device_tree() {
    echo -e "YELLOWGeneratingdevicetreeforXen...{YELLOW}Generating device tree for Xen...
YELLOWGeneratingdevicetreeforXen...{NC}"

local dt_source="${IMAGE_DIR}/xen-qemu.dts"
local dt_blob="${IMAGE_DIR}/xen-qemu.dtb"

cat > "$dt_source" <<'EOF'
/dts-v1/;
/ {
#address-cells = <2>;
#size-cells = <2>;
compatible = "linux,dummy-virt";
chosen {
    bootargs = "console=hvc0 earlycon=xenboot";
    xen,xen-bootargs = "console=dtuart dtuart=/pl011@9000000 dom0_mem=1024M dom0_max_vcpus=4";
    xen,dom0-bootargs = "console=hvc0 root=/dev/vda rw";
    
    /* Dom0 kernel */
    module@0 {
        compatible = "multiboot,kernel", "multiboot,module";
        reg = <0x0 0x44000000 0x0 0x02000000>;
    };
    
    /* Dom0 rootfs */
    module@1 {
        compatible = "multiboot,ramdisk", "multiboot,module";
        reg = <0x0 0x46000000 0x0 0x10000000>;
    };
};
};
EOF
dtc -I dts -O dtb -o "$dt_blob" "$dt_source"
echo -e "${GREEN}✓ Device tree created${NC}"
}
Launch QEMU
launch_qemu() {
    echo -e "YELLOWLaunchingQEMUwithXenhypervisor...{YELLOW}Launching QEMU with Xen hypervisor...
YELLOWLaunchingQEMUwithXenhypervisor...{NC}"
    echo ""
    echo "Configuration:"
    echo "  Memory: ${QEMU_MEMORY}MB"
    echo "  CPUs: ${QEMU_CPUS}"
    echo "  HMI VNC: localhost
:5900 (password: agl)"
echo "  VSS Broker: http://localhost:8090"
echo ""
echo "Press Ctrl+A, X to exit QEMU"
echo ""
sleep 2

# Build QEMU command
qemu-system-aarch64 \
    -machine "${QEMU_MACHINE}" \
    -cpu cortex-a57 \
    -smp "${QEMU_CPUS}" \
    -m "${QEMU_MEMORY}" \
    -kernel "${IMAGE_DIR}/xen" \
    -append "console=dtuart dtuart=/pl011@9000000 dom0_mem=1024M" \
    -device loader,file="${IMAGE_DIR}/Image",addr=0x44000000 \
    -device loader,file="${IMAGE_DIR}/agl-demo-platform-dom0.ext4",addr=0x46000000 \
    -drive file="${IMAGE_DIR}/agl-demo-platform-dom0.ext4",if=none,id=hd0,format=raw \
    -device virtio-blk-device,drive=hd0 \
    -netdev "${QEMU_NET}" \
    -device virtio-net-device,netdev=net0 \
    -serial mon:stdio \
    -display none \
    -nographic \
    || {
        echo -e "${RED}QEMU failed to start${NC}"
        exit 1
    }
}
Post-boot: Create VMs (called from dom0)
setup_vms() {
    echo -e "YELLOWSettingupVMsandcontainers...{YELLOW}Setting up VMs and containers...
YELLOWSettingupVMsandcontainers...{NC}"
    echo "Run this inside dom0 after boot:"
    echo ""
    echo "  xl list  # Verify dom0 is running"
    echo "  /mnt/create-vms.sh  # Create HMI, Zephyr, and container"
    echo ""
}

Main
main() {
check_images
create_device_tree
echo -e "${YELLOW}Starting QEMU in 3 seconds...${NC}"
echo "(VMs will be created manually from dom0 after boot)"
sleep 3

launch_qemu
}
main "$@"
