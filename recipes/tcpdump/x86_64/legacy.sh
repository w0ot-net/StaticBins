#!/bin/bash
# Build statically linked tcpdump on Alpine Linux
# This script builds both libpcap and tcpdump statically

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Version configuration
LIBPCAP_VERSION="1.10.4"
TCPDUMP_VERSION="4.99.4"

# Build directory
BUILD_DIR="/tmp/tcpdump-static-build"
INSTALL_PREFIX="/opt/tcpdump-static"

echo -e "${GREEN}Starting static tcpdump build process...${NC}"

# Function to check if running on Alpine
check_alpine() {
    if [ ! -f /etc/alpine-release ]; then
        echo -e "${RED}Warning: This script is designed for Alpine Linux${NC}"
        echo "Continue anyway? (y/n)"
        read -r response
        if [ "$response" != "y" ]; then
            exit 1
        fi
    fi
}

# Function to install dependencies
install_dependencies() {
    echo -e "${YELLOW}Installing build dependencies...${NC}"
    apk update
    apk add --no-cache \
        gcc \
        musl-dev \
        make \
        flex \
        bison \
        linux-headers \
        wget \
        tar \
        cmake \
        build-base \
        libpcap-dev \
        openssl-dev \
        openssl-libs-static \
        binutils
}

# Function to create build directory
setup_build_dir() {
    echo -e "${YELLOW}Setting up build directory...${NC}"
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"
}

# Function to download and extract source
download_source() {
    local name=$1
    local version=$2
    local url=$3

    echo -e "${YELLOW}Downloading $name $version...${NC}"
    wget -q --show-progress "$url" -O "$name-$version.tar.gz"
    tar -xzf "$name-$version.tar.gz"
}

# Function to build libpcap statically
build_libpcap() {
    echo -e "${GREEN}Building libpcap statically...${NC}"

    download_source "libpcap" "$LIBPCAP_VERSION" \
        "https://www.tcpdump.org/release/libpcap-${LIBPCAP_VERSION}.tar.gz"

    cd "libpcap-${LIBPCAP_VERSION}"

    # Configure for static build
    CFLAGS="-static -O2" \
    LDFLAGS="-static" \
    ./configure \
        --prefix="$INSTALL_PREFIX" \
        --disable-shared \
        --enable-static \
        --disable-dbus \
        --disable-bluetooth \
        --disable-canusb \
        --disable-can \
        --disable-wireless \
        --without-libnl

    make -j$(nproc)
    make install

    cd "$BUILD_DIR"
}

# Function to build tcpdump statically
build_tcpdump() {
    echo -e "${GREEN}Building tcpdump statically...${NC}"

    download_source "tcpdump" "$TCPDUMP_VERSION" \
        "https://www.tcpdump.org/release/tcpdump-${TCPDUMP_VERSION}.tar.gz"

    cd "tcpdump-${TCPDUMP_VERSION}"

    # Configure for static build with custom libpcap location
    CFLAGS="-static -O2 -I${INSTALL_PREFIX}/include" \
    LDFLAGS="-static -L${INSTALL_PREFIX}/lib" \
    LIBS="-lpcap" \
    ./configure \
        --prefix="$INSTALL_PREFIX" \
        --disable-shared \
        --without-crypto \
        --without-cap-ng \
        --without-smi

    # Modify Makefile to ensure static linking
    sed -i 's/LDFLAGS = /LDFLAGS = -static /' Makefile

    make -j$(nproc)
    make install

    cd "$BUILD_DIR"
}

# Function to verify static linking
verify_static() {
    echo -e "${YELLOW}Verifying static linking...${NC}"

    if [ -f "${INSTALL_PREFIX}/sbin/tcpdump" ]; then
        TCPDUMP_BIN="${INSTALL_PREFIX}/sbin/tcpdump"
    elif [ -f "${INSTALL_PREFIX}/bin/tcpdump" ]; then
        TCPDUMP_BIN="${INSTALL_PREFIX}/bin/tcpdump"
    else
        echo -e "${RED}tcpdump binary not found!${NC}"
        return 1
    fi

    # Multiple methods to verify static linking
    echo -e "${YELLOW}Checking binary type...${NC}"

    # Method 1: Use file command to check
    FILE_OUTPUT=$(file "$TCPDUMP_BIN")
    echo "File output: $FILE_OUTPUT"

    # Method 2: Check with readelf if available
    if command -v readelf >/dev/null 2>&1; then
        echo -e "\n${YELLOW}Checking dynamic sections with readelf:${NC}"
        if readelf -d "$TCPDUMP_BIN" 2>/dev/null | grep -q "NEEDED"; then
            echo -e "${YELLOW}Dynamic libraries found:${NC}"
            readelf -d "$TCPDUMP_BIN" | grep NEEDED
        else
            echo -e "${GREEN}No dynamic libraries needed (static binary)${NC}"
        fi
    fi

    # Method 3: On Alpine/musl, ldd behaves differently
    echo -e "\n${YELLOW}Checking with ldd:${NC}"
    LDD_OUTPUT=$(ldd "$TCPDUMP_BIN" 2>&1)

    # On Alpine with musl, static binaries show "Not a valid dynamic program"
    if echo "$LDD_OUTPUT" | grep -q "Not a valid dynamic program"; then
        echo -e "${GREEN}Success! tcpdump is statically linked (musl static binary)${NC}"
        STATIC_VERIFIED=true
    elif echo "$LDD_OUTPUT" | grep -q "not a dynamic executable"; then
        echo -e "${GREEN}Success! tcpdump is statically linked${NC}"
        STATIC_VERIFIED=true
    elif echo "$LDD_OUTPUT" | grep -q "statically linked"; then
        echo -e "${GREEN}Success! tcpdump is statically linked${NC}"
        STATIC_VERIFIED=true
    else
        echo -e "${YELLOW}ldd output:${NC}"
        echo "$LDD_OUTPUT"

        # Check if it only depends on libc
        if echo "$LDD_OUTPUT" | grep -v "linux-vdso" | grep -v "ld-musl" | grep -q "\.so"; then
            echo -e "${RED}Warning: Binary has dynamic dependencies${NC}"
            STATIC_VERIFIED=false
        else
            echo -e "${GREEN}Binary appears to be static (only vdso/interpreter references)${NC}"
            STATIC_VERIFIED=true
        fi
    fi

    if [ "$STATIC_VERIFIED" = true ]; then
        echo -e "\n${GREEN}Static linking verified successfully!${NC}"
        echo -e "${GREEN}Binary location: $TCPDUMP_BIN${NC}"

        # Show file info
        echo -e "\n${YELLOW}Binary information:${NC}"
        ls -lh "$TCPDUMP_BIN"

        # Test basic functionality
        echo -e "\n${YELLOW}Testing tcpdump:${NC}"
        "$TCPDUMP_BIN" --version

        return 0
    else
        return 1
    fi
}

# Function to create standalone package
create_package() {
    echo -e "${YELLOW}Creating standalone package...${NC}"

    PACKAGE_DIR="$BUILD_DIR/tcpdump-static-package"
    mkdir -p "$PACKAGE_DIR"

    # Copy binary
    cp "$TCPDUMP_BIN" "$PACKAGE_DIR/"

    # Strip debug symbols to reduce size
    strip "$PACKAGE_DIR/tcpdump"

    # Create tarball
    cd "$BUILD_DIR"
    tar -czf "tcpdump-static-${TCPDUMP_VERSION}-alpine.tar.gz" -C "$PACKAGE_DIR" tcpdump

    echo -e "${GREEN}Package created: $BUILD_DIR/tcpdump-static-${TCPDUMP_VERSION}-alpine.tar.gz${NC}"
    ls -lh "$BUILD_DIR/tcpdump-static-${TCPDUMP_VERSION}-alpine.tar.gz"
}

# Function to cleanup
cleanup() {
    echo -e "${YELLOW}Cleaning up build artifacts...${NC}"
    cd /
    rm -rf "$BUILD_DIR/libpcap-${LIBPCAP_VERSION}"
    rm -rf "$BUILD_DIR/tcpdump-${TCPDUMP_VERSION}"
    rm -f "$BUILD_DIR"/*.tar.gz
}

# Main execution
main() {
    echo -e "${GREEN}=== Static tcpdump Builder for Alpine ===${NC}"

    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}Please run as root (use sudo)${NC}"
        exit 1
    fi

    check_alpine
    install_dependencies
    setup_build_dir
    build_libpcap
    build_tcpdump

    if verify_static; then
        create_package

        echo -e "\n${GREEN}Build completed successfully!${NC}"
        echo -e "Static tcpdump binary: ${INSTALL_PREFIX}/sbin/tcpdump or ${INSTALL_PREFIX}/bin/tcpdump"
        echo -e "Packaged binary: $BUILD_DIR/tcpdump-static-${TCPDUMP_VERSION}-alpine.tar.gz"

        # Optional cleanup
        echo -e "\n${YELLOW}Clean up build files? (y/n)${NC}"
        read -r response
        if [ "$response" = "y" ]; then
            cleanup
        fi
    else
        echo -e "${RED}Build verification failed!${NC}"
        exit 1
    fi
}

# Run main function
main "$@"
