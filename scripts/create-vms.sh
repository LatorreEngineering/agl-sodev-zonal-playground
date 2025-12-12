```bash
#!/bin/bash
# AGL SoDeV Zonal Playground - VM Creation Script
# Creates HMI VM, Zephyr RT VM, and Telematics container

set -e
set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Paths (adjust for dom0 vs development)
if [ -d "/usr/local/share/agl-sodev" ]; then
    # Running in dom0
    CONFIG_DIR="/usr/local/share/agl-sodev/xl-configs"
    IMAGE_DIR="/usr/local/share/agl-sodev/images"
else
    # Running from repo
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    REPO_ROOT="$(dirname "$SCRIPT_DIR")"
    CONFIG_DIR="${REPO_ROOT}/xl-configs"
    IMAGE_DIR="${REPO_ROOT}/images"
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}AGL SoDeV - VM Creation${NC}"
echo -e "${GREEN}========================================${NC}"

# Check Xen is running
check_xen() {
    echo -e "${YELLOW}[1/4] Checking Xen hypervisor...${NC}"
    
    if ! command -v xl &> /dev/null; then
        echo -e "${RED}ERROR: xl command not found. Are you in dom0?${NC}"
        exit 1
    fi
    
    if ! xl info &> /dev/null; then
        echo -e "${RED}ERROR: Cannot communicate with Xen. Is the hypervisor running?${NC}"
        exit 1
    fi
    
    local xen_version=$(xl info | grep "xen_version" | awk '{print $3}')
    echo "Xen version: $xen_version"
    
    echo -e "${GREEN}✓ Xen hypervisor ready${NC}"
}

# Create HMI VM
create_hmi_vm() {
    echo -e "${YELLOW}[2/4] Creating HMI VM (AGL demo platform)...${NC}"
    
    local vm_config="${CONFIG_DIR}/hmi-vm.cfg"
    
    if [ ! -f "$vm_config" ]; then
        echo -e "${RED}ERROR: HMI VM config not found: $vm_config${NC}"
        exit 1
    fi
    
    # Check if VM already exists
    if xl list | grep -q "hmi-vm"; then
        echo "HMI VM already running. Destroying..."
        xl destroy hmi-vm || true
    fi
    
    # Create VM
    echo "Starting HMI VM with config: $vm_config"
    xl create "$vm_config"
    
    # Wait for VM to boot
    sleep 5
    
    if xl list | grep -q "hmi-vm"; then
        echo -e "${GREEN}✓ HMI VM created successfully${NC}"
        xl list | grep hmi-vm
    else
        echo -e "${RED}ERROR: HMI VM failed to start. Check 'xl dmesg'${NC}"
        exit 1
    fi
}

# Create Zephyr RT VM
create_zephyr_vm() {
    echo -e "${YELLOW}[3/4] Creating Zephyr RT VM (CAN simulator)...${NC}"
    
    local vm_config="${CONFIG_DIR}/zephyr-rt-vm.cfg"
    
    if [ ! -f "$vm_config" ]; then
        echo -e "${RED}ERROR: Zephyr VM config not found: $vm_config${NC}"
        exit 1
    fi
    
    # Check if VM already exists
    if xl list | grep -q "zephyr-rt-vm"; then
        echo "Zephyr RT VM already running. Destroying..."
        xl destroy zephyr-rt-vm || true
    fi
    
    # Create VM
    echo "Starting Zephyr RT VM with config: $vm_config"
    xl create "$vm_config"
    
    # Wait for VM to initialize
    sleep 3
    
    if xl list | grep -q "zephyr-rt-vm"; then
        echo -e "${GREEN}✓ Zephyr RT VM created successfully${NC}"
        xl list | grep zephyr-rt-vm
        
        # Pin VCPUs for real-time performance
        echo "Pinning Zephyr VCPUs to physical cores 6-7..."
        xl vcpu-pin zephyr-rt-vm 0 6
        xl vcpu-pin zephyr-rt-vm 1 7
    else
        echo -e "${RED}ERROR: Zephyr RT VM failed to start${NC}"
        exit 1
    fi
}

# Create telematics container
create_telematics_container() {
    echo -e "${YELLOW}[4/4] Creating telematics container (VSS broker)...${NC}"
    
    if ! command -v podman &> /dev/null; then
        echo -e "${YELLOW}WARNING: Podman not found. Skipping container creation.${NC}"
        return
    fi
    
    local container_config="${CONFIG_DIR}/telematics-podman.yml"
    
    # Check if container already exists
    if podman ps -a | grep -q "telematics-vss"; then
        echo "Telematics container already exists. Removing..."
        podman rm -f telematics-vss || true
    fi
    
    # Start container using quadlet config
    if [ -f "$container_config" ]; then
        echo "Starting VSS broker container..."
        
        # Run container directly (simplified version)
        podman run -d \
            --name telematics-vss \
            --network host \
            -p 8090:8090 \
            ghcr.io/eclipse/kuksa.val/databroker:latest \
            || {
                echo -e "${RED}ERROR: Failed to start container${NC}"
                exit 1
            }
        
        sleep 3
        
        if podman ps | grep -q "telematics-vss"; then
            echo -e "${GREEN}✓ Telematics container created successfully${NC}"
            podman ps | grep telematics-vss
        else
            echo -e "${RED}ERROR: Container failed to start${NC}"
            exit 1
        fi
    else
        echo -e "${YELLOW}WARNING: Container config not found. Using default setup.${NC}"
    fi
}

# Print status summary
print_status() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}VM/Container Status${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    
    echo "Xen VMs:"
    xl list
    echo ""
    
    if command -v podman &> /dev/null; then
        echo "Containers:"
        podman ps
        echo ""
    fi
    
    echo "Access points:"
    echo "  - HMI VM console: xl console hmi-vm"
    echo "  - Zephyr console: xl console zephyr-rt-vm"
    echo "  - VSS Broker: http://localhost:8090"
    echo ""
    echo "Monitoring:"
    echo "  - Xen trace: xentrace -D"
    echo "  - VM stats: xl top"
    echo "  - Container logs: podman logs -f telematics-vss"
    echo ""
}

# Main
main() {
    check_xen
    create_hmi_vm
    create_zephyr_vm
    create_telematics_container
    print_status
    
    echo -e "${GREEN}All components started successfully!${NC}"
}

main "$@"
```
