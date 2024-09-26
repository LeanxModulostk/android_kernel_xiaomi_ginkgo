#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status.

ZIPNAME="Lean.Kernel-Ginkgo"
ZIMAGE_DIR="$(pwd)/out/arch/arm64/boot"
TIME="$(date "+%Y%m%d-%H%M%S")"
BUILD_START=$(date +"%s")
TC_DIR="$HOME/tc/weebx"
AK3_DIR="$HOME/android/AnyKernel3"
DEFCONFIG="vendor/lean-perf_defconfig"

# Function to download and setup Clang
download_and_setup_clang() {
    echo "Downloading WeebX Clang..."
    CLANG_URL=$(curl -s https://raw.githubusercontent.com/v3kt0r-87/Clang-Stable/main/clang-weebx.txt)
    
    if ! curl --output /dev/null --silent --head --fail "$CLANG_URL"; then
        echo "Failed to fetch Clang URL. Aborting..."
        return 1
    fi

    echo "Clang URL: $CLANG_URL"
    
    ARCHIVE_NAME="weebx-clang.tar.gz"
    DOWNLOAD_PATH="$HOME/tc/$ARCHIVE_NAME"
    
    echo "Downloading Clang to $DOWNLOAD_PATH..."
    if ! wget "$CLANG_URL" -O "$DOWNLOAD_PATH"; then
        echo "Failed to download Clang. Aborting..."
        return 1
    fi
    
    echo "Extracting Clang..."
    if ! tar -xzf "$DOWNLOAD_PATH" -C "${TC_DIR}" --strip-components=1; then
        echo "Failed to extract Clang. Aborting..."
        return 1
    fi

    echo "Removing downloaded archive..."
    rm -f "$DOWNLOAD_PATH"
    
    echo "Clang setup completed successfully."
    return 0
}

# Create TC_DIR if it doesn't exist
mkdir -p "$TC_DIR"

# Check for Clang binary
if [ ! -f "${TC_DIR}/bin/clang" ]; then
    echo "Clang binary not found. Attempting to download..."
    if ! download_and_setup_clang; then
        echo "Failed to setup Clang. Aborting..."
        exit 1
    fi
else
    echo "Clang binary found at ${TC_DIR}/bin/clang."
fi

# Verify Clang version
CLANG_VERSION=$("${TC_DIR}/bin/clang" --version | head -n 1)
echo "Detected Clang version: $CLANG_VERSION"

export PATH="${TC_DIR}/bin:$PATH"
export ARCH=arm64
export SUBARCH=arm64

export KBUILD_COMPILER_STRING="$CLANG_VERSION"
export KBUILD_BUILD_USER="Telegram"
export KBUILD_BUILD_HOST="LeanHijosdesusMadres"

if [[ $1 = "-r" || $1 = "--regen" ]]; then
    make O=out ARCH=arm64 $DEFCONFIG savedefconfig
    cp out/defconfig arch/arm64/configs/$DEFCONFIG
    exit
fi

if [[ $1 = "-c" || $1 = "--clean" ]]; then
    rm -rf out
fi

mkdir -p out
make O=out ARCH=arm64 $DEFCONFIG

echo -e "\nStarting compilation...\n"
make -j$(nproc --all) O=out ARCH=arm64 CC=clang LD=ld.lld AR=llvm-ar AS=llvm-as NM=llvm-nm OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip CROSS_COMPILE=aarch64-linux-android-

if [ -f "$ZIMAGE_DIR/Image.gz-dtb" ] && [ -f "$ZIMAGE_DIR/dtbo.img" ]; then
    echo -e "\nKernel compiled successfully! Zipping up...\n"
    
    if [ ! -d "$AK3_DIR" ]; then
        echo "AnyKernel3 directory not found. Cloning..."
        if ! git clone -q https://github.com/LeanxModulostk/AnyKernel3 "$AK3_DIR"; then
            echo -e "\nAnyKernel3 repo not found locally and cloning failed! Aborting..."
            exit 1
        fi
    fi

    mkdir -p tmp
    cp -fp "$ZIMAGE_DIR/Image.gz" tmp
    cp -fp "$ZIMAGE_DIR/dtbo.img" tmp
    cp -fp "$ZIMAGE_DIR/dtb" tmp
    cp -rp "$AK3_DIR/"* tmp

    cd tmp
    7za a -mx9 tmp.zip *
    cd ..
    
    rm -f *.zip
    cp -fp tmp/tmp.zip "AOSP-${ZIPNAME}-$TIME.zip"
    rm -rf tmp
    echo $TIME
else
    echo -e "\nCompilation failed!"
    exit 1
fi
