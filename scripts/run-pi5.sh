```bash
#!/bin/bash
# AGL SoDeV Zonal Playground - Raspberry Pi 5 Deployment
# Flashes AGL image to SD card and provides boot configuration

set -e
set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
IMAGE_DIR="${REPO_ROOT}/images"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}ERROR: This script must be run as root (for dd command)${NC}"
    echo "Usage: sudo $0 /dev/sdX"
    exit 1
fi

# Check SD card argument
if [ $# -ne 1 ]; then
    echo "Usage: sudo $0 /dev/sdX"
    echo "Example: sudo $0 /dev/sdb"
    exit 1
fi

SD_DEVICE="$1"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}AGL SoDeV - Raspberry Pi 5 Deployment${NC}"
echo -e "${GREEN}========================================${NC}"

# Validate SD device
validate_device() {
    echo -e "${YELLOW}Validating target device: ${SD_DEVICE}${NC}"
    
    if [ ! -b "$SD_DEVICE" ]; then
        echo -e "${RED}ERROR: $SD_DEVICE is not a block device${NC}"
        exit 1
    fi
    
    # Check if it's mounted
    if mount | grep -q "$SD_DEVICE"; then
        echo -e "${YELLOW}WARNING: $SD_DEVICE is currently mounted${NC}"
        read -p "Unmount all partitions? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            umount "${SD_DEVICE}"* 2>/dev/null || true
        else
            exit 1
        fi
    fi
    
    # Final confirmation
    echo -e "${RED}WARNING: This will ERASE all data on $SD_DEVICE${NC}"
    lsblk "$SD_DEVICE"
    read -p "Continue? Type 'YES' to confirm: " confirm
    
    if [ "$confirm" != "YES" ]; then
        echo "Aborted."
        exit 0
    fi
    
    echo -e "${GREEN}✓ Device validated${NC}"
}

# Flash image
flash_image() {
    echo -e "${YELLOW}Flashing AGL image to SD card...${NC}"
    
    local image_file="${IMAGE_DIR}/agl-demo-platform-qemuarm64.wic.xz"
    
    if [ ! -f "$image_file" ]; then
        echo -e "${RED}ERROR: Image not found: $image_file${NC}"
        echo "Run ./scripts/build.sh with MACHINE=raspberrypi5 first"
        exit 1
    fi
    
    echo "Decompressing and writing (this takes 5-10 minutes)..."
    xzcat "$image_file" | dd of="$SD_DEVICE" bs=4M status=progress conv=fsync
    
    sync
    echo -e "${GREEN}✓ Image flashed successfully${NC}"
}

# Configure boot partition
configure_boot() {
    echo -e "${YELLOW}Configuring Xen boot parameters...${NC}"
    
    # Mount boot partition
    mkdir -p /mnt/pi5-boot
    mount "${SD_DEVICE}1" /mnt/pi5-boot || {
        echo -e "${RED}ERROR: Failed to mount boot partition${NC}"
        exit 1
    }
    
    # Create config.txt for Xen
    cat > /mnt/pi5-boot/config.txt <<'EOF'
# Raspberry Pi 5 - Xen Hypervisor Boot Configuration

# Enable UART for Xen console (115200 baud)
enable_uart=1
uart_2ndstage=1

# ARM 64-bit mode
arm_64bit=1

# Xen boot setup
kernel=xen
device_tree_address=0x44000000
device_tree_end=0x45000000

# Dom0 kernel (AGL Linux)
kernel_address=0x46000000
ramdisk_address=0x50000000

# Memory allocation
total_mem=4096
gpu_mem=256

# Xen hypervisor arguments
xen_cmdline=console=dtuart dtuart=/pl011@fe201000 dom0_mem=1024M dom0_max_vcpus=4 loglvl=all guest_loglvl=all

# Dom0 kernel arguments
dom0_cmdline=console=hvc0 root=/dev/mmcblk0p2 rootwait rw

# Enable I2C, SPI for peripheral access
dtparam=i2c_arm=on
dtparam=spi=on

# Disable Bluetooth (conflicts with UART)
dtoverlay=disable-bt

# Performance governor
arm_freq=2400
over_voltage=4
EOF
    
    # Copy Xen and kernel
    echo "Copying Xen hypervisor and kernel..."
    cp "${IMAGE_DIR}/xen" /mnt/pi5-boot/
    cp "${IMAGE_DIR}/Image" /mnt/pi5-boot/kernel8.img
    
    # Copy device tree overlays
    if [ -f "${REPO_ROOT}/overlays/virtio-automotive.dtb" ]; then
        cp "${REPO_ROOT}/overlays/virtio-automotive.dtb" /mnt/pi5-boot/overlays/
    fi
    
    sync
    umount /mnt/pi5-boot
    rmdir /mnt/pi5-boot
    
    echo -e "${GREEN}✓ Boot configuration complete${NC}"
}

# Print next steps
print_instructions() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Deployment Complete!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "Next steps:"
    echo ""
    echo "1. HARDWARE SETUP:"
    echo "   - Insert SD card into Raspberry Pi 5"
    echo "   - Connect UART adapter to GPIO 14/15:"
    echo "     * Pin 6  (GND) → GND"
    echo "     * Pin 8  (TX)  → RX on adapter"
    echo "     * Pin 10 (RX)  → TX on adapter"
    echo "   - Connect HDMI monitor (for HMI VM)"
    echo "   - Connect Ethernet cable"
    echo ""
    echo "2. BOOT PROCESS:"
    echo "   - Open serial terminal: screen /dev/ttyUSB0 115200"
    echo "   - Power on Pi 5"
    echo "   - Watch for Xen boot messages"
    echo "   - Login to dom0: root / agl"
    echo ""
    echo "3. CREATE VMs:"
    echo "   - From dom0: /usr/local/bin/create-vms.sh"
    echo "   - Verify: xl list"
    echo ""
    echo "4. ACCESS SERVICES:"
    echo "   - HMI: HDMI output (Qt interface)"
    echo "   - VSS Broker: http://<pi-ip>:8090"
    echo "   - Zephyr console: xl console zephyr-rt-vm"
    echo ""
    echo "Troubleshooting:"
    echo "   - No output: Check UART connections and baud rate"
    echo "   - Boot fails: Verify config.txt in boot partition"
    echo "   - VMs don't start: Check 'xl dmesg' for errors"
    echo ""
}

# Main
main() {
    validate_device
    flash_image
    configure_boot
    print_instructions
}

main "$@"
```
