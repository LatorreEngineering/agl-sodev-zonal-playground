# AGL SoDeV Zonal Playground - Build Script
# Builds agl-demo-platform with Xen dom0 support

set -e  # Exit on error
set -u  # Exit on undefined variable

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
AGL_WORKSPACE="${REPO_ROOT}/agl-workspace"
BUILD_DIR="${AGL_WORKSPACE}/build"
OUTPUT_DIR="${REPO_ROOT}/images"
LOCAL_CONF="${REPO_ROOT}/conf/local.conf"

# Default target
MACHINE="${MACHINE:-qemuarm64}"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}AGL SoDeV Zonal Playground - Build${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Check prerequisites
check_dependencies() {
    echo -e "${YELLOW}[1/6] Checking dependencies...${NC}"
    
    local missing_deps=()
    
    for cmd in repo bitbake git python3 dtc qemu-system-aarch64; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo -e "${RED}ERROR: Missing dependencies: ${missing_deps[*]}${NC}"
        echo "Install with: sudo apt-get install repo python3 git device-tree-compiler qemu-system-arm"
        exit 1
    fi
    
    # Check disk space (need 50GB+)
    local available_space=$(df -BG "$REPO_ROOT" | tail -1 | awk '{print $4}' | sed 's/G//')
    if [ "$available_space" -lt 50 ]; then
        echo -e "${RED}WARNING: Low disk space ($available_space GB). Need 50GB+ for build.${NC}"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    echo -e "${GREEN}✓ All dependencies found${NC}"
}

# Initialize AGL workspace
init_workspace() {
    echo -e "${YELLOW}[2/6] Initializing AGL workspace...${NC}"
    
    if [ ! -d "$AGL_WORKSPACE" ]; then
        echo -e "${RED}ERROR: AGL workspace not found. Run 'repo sync' first:${NC}"
        echo "  cd $REPO_ROOT"
        echo "  mkdir agl-workspace && cd agl-workspace"
        echo "  repo init -u ../manifests -m default.xml"
        echo "  repo sync -j\$(nproc)"
        exit 1
    fi
    
    cd "$AGL_WORKSPACE"
    
    # Source AGL setup script
    if [ ! -f "aglsetup.sh" ]; then
        echo -e "${RED}ERROR: aglsetup.sh not found. Repo sync incomplete?${NC}"
        exit 1
    fi
    
    # Run aglsetup.sh if build dir doesn't exist
    if [ ! -d "$BUILD_DIR" ]; then
        echo "Running aglsetup.sh for machine: $MACHINE"
        source ./aglsetup.sh -m "$MACHINE" -b build agl-demo agl-devel
    fi
    
    echo -e "${GREEN}✓ Workspace initialized${NC}"
}

# Apply custom local.conf
apply_config() {
    echo -e "${YELLOW}[3/6] Applying custom Yocto configuration...${NC}"
    
    if [ ! -f "$LOCAL_CONF" ]; then
        echo -e "${RED}ERROR: local.conf not found at $LOCAL_CONF${NC}"
        exit 1
    fi
    
    # Backup original local.conf
    if [ -f "${BUILD_DIR}/conf/local.conf" ]; then
        cp "${BUILD_DIR}/conf/local.conf" "${BUILD_DIR}/conf/local.conf.bak"
    fi
    
    # Copy our custom local.conf
    cp "$LOCAL_CONF" "${BUILD_DIR}/conf/local.conf"
    
    # Override MACHINE if specified
    if [ -n "${MACHINE:-}" ]; then
        sed -i "s/^MACHINE ?= .*/MACHINE ?= \"$MACHINE\"/" "${BUILD_DIR}/conf/local.conf"
    fi
    
    echo -e "${GREEN}✓ Configuration applied${NC}"
}

# Build AGL image
build_image() {
    echo -e "${YELLOW}[4/6] Building AGL demo platform (this takes 60-90 min on first run)...${NC}"
    
    cd "$BUILD_DIR"
    
    # Source Yocto environment
    source ../external/poky/oe-init-build-env .
    
    # Start build
    local start_time=$(date +%s)
    
    if ! bitbake agl-demo-platform-crosssdk; then
        echo -e "${RED}ERROR: Build failed. Check logs in ${BUILD_DIR}/tmp/log/cooker/${MACHINE}/console-latest.log${NC}"
        exit 1
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo -e "${GREEN}✓ Build completed in $((duration / 60)) minutes${NC}"
}

# Extract and organize images
organize_images() {
    echo -e "${YELLOW}[5/6] Organizing output images...${NC}"
    
    local deploy_dir="${BUILD_DIR}/tmp/deploy/images/${MACHINE}"
    
    if [ ! -d "$deploy_dir" ]; then
        echo -e "${RED}ERROR: Deploy directory not found: $deploy_dir${NC}"
        exit 1
    fi
    
    # Create output directory
    mkdir -p "$OUTPUT_DIR"
    
    # Copy relevant images
    echo "Copying images to $OUTPUT_DIR..."
    
    # Kernel and device tree
    if [ -f "$deploy_dir/Image" ]; then
        cp "$deploy_dir/Image" "$OUTPUT_DIR/"
    fi
    
    if [ -f "$deploy_dir/Image-${MACHINE}.bin" ]; then
        cp "$deploy_dir/Image-${MACHINE}.bin" "$OUTPUT_DIR/"
    fi
    
    # Root filesystem
    if [ -f "$deploy_dir/agl-demo-platform-${MACHINE}.ext4" ]; then
        cp "$deploy_dir/agl-demo-platform-${MACHINE}.ext4" "$OUTPUT_DIR/agl-demo-platform-dom0.ext4"
    fi
    
    # Disk image (for hardware)
    if [ -f "$deploy_dir/agl-demo-platform-${MACHINE}.wic.xz" ]; then
        cp "$deploy_dir/agl-demo-platform-${MACHINE}.wic.xz" "$OUTPUT_DIR/"
    fi
    
    # Xen hypervisor
    if [ -f "$deploy_dir/xen" ]; then
        cp "$deploy_dir/xen" "$OUTPUT_DIR/"
    fi
    
    # Device tree blobs
    find "$deploy_dir" -name "*.dtb" -exec cp {} "$OUTPUT_DIR/" \;
    
    echo -e "${GREEN}✓ Images organized in $OUTPUT_DIR${NC}"
    ls -lh "$OUTPUT_DIR"
}

# Download Zephyr image (prebuilt for quick testing)
download_zephyr() {
    echo -e "${YELLOW}[6/6] Downloading Zephyr RT image...${NC}"
    
    local zephyr_url="https://github.com/zephyrproject-rtos/zephyr/releases/download/v3.5.0/zephyr-qemu_cortex_a53.bin"
    local zephyr_sha256="a1b2c3d4e5f6789012345678901234567890123456789012345678901234abcd"  # Example checksum
    
    cd "$OUTPUT_DIR"
    
    if [ ! -f "zephyr-rt.bin" ]; then
        echo "Downloading prebuilt Zephyr image..."
        
        # Note: Use a real URL for production; this is a placeholder
        # For now, create a dummy file
        echo "WARNING: Using dummy Zephyr image. Replace with real build."
        dd if=/dev/zero of=zephyr-rt.bin bs=1M count=1
        
        # In production, use:
        # wget -O zephyr-rt.bin "$zephyr_url"
        # echo "$zephyr_sha256  zephyr-rt.bin" | sha256sum -c -
    fi
    
    echo -e "${GREEN}✓ Zephyr image ready${NC}"
}

# Main execution
main() {
    check_dependencies
    init_workspace
    apply_config
    build_image
    organize_images
    download_zephyr
    
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Build Complete!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Run on QEMU: ./scripts/run-qemu.sh"
    echo "  2. Flash to Pi5: ./scripts/run-pi5.sh /dev/sdX"
    echo ""
    echo "Output images: $OUTPUT_DIR"
}

main "$@"
