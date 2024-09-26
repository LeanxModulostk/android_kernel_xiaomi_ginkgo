#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status.

SECONDS=0 # builtin bash timer
ZIPNAME="Lean.Kernel-Ginkgo$(TZ=Europe/Istanbul date +"%Y%m%d-%H%M").zip"
TC_DIR="$HOME/tc/weebx"
GCC_64_DIR="$HOME/tc/aarch64-linux-android-4.9"
GCC_32_DIR="$HOME/tc/arm-linux-androideabi-4.9"
AK3_DIR="$HOME/android/AnyKernel3"
DEFCONFIG="vendor/ginkgo-perf_defconfig"

# Clang setup
if ! [ -d "${TC_DIR}" ]; then
    echo "Clang not found! Downloading WeebX Clang..."
    CLANG_URL=$(curl -s https://raw.githubusercontent.com/v3kt0r-87/Clang-Stable/main/clang-weebx.txt)
    if [ -z "$CLANG_URL" ]; then
        echo "Failed to fetch Clang URL. Aborting..."
        exit 1
    fi
    echo "Clang URL: $CLANG_URL"
    
    ARCHIVE_NAME="weebx-clang.tar.gz"
    DOWNLOAD_PATH="$HOME/tc/$ARCHIVE_NAME"
    
    echo "Downloading Clang to $DOWNLOAD_PATH..."
    if ! wget -P "$HOME/tc" "$CLANG_URL" -O "$DOWNLOAD_PATH"; then
        echo "Failed to download Clang. Aborting..."
        exit 1
    fi
    
    if [ ! -f "$DOWNLOAD_PATH" ]; then
        echo "Downloaded file not found at $DOWNLOAD_PATH. Aborting..."
        exit 1
    fi

    echo "Creating directory ${TC_DIR}..."
    mkdir -p "${TC_DIR}"
    
    echo "Extracting Clang..."
    if ! tar -xvf "$DOWNLOAD_PATH" -C "${TC_DIR}"; then
        echo "Failed to extract Clang. Aborting..."
        exit 1
    fi

    echo "Removing downloaded archive..."
    rm -f "$DOWNLOAD_PATH"
    
    echo "Clang setup completed successfully."
else
    echo "Clang directory found at ${TC_DIR}. Skipping download."
fi

export PATH="${TC_DIR}/bin:$PATH"
export KBUILD_COMPILER_STRING="$("${TC_DIR}/bin/clang" --version | head -n 1 | perl -pe 's/\(http.*?\)//gs' | sed -e 's/  */ /g' -e 's/[[:space:]]*$//')"

export KBUILD_BUILD_USER="linux"
export KBUILD_BUILD_HOST="LeanHijosdesusMadres"
export KBUILD_BUILD_VERSION="1"

# Rest of the script remains the same...
# (GCC setup, compilation process, etc.)

# GCC setup (unchanged)
if ! [ -d "${GCC_64_DIR}" ]; then
    echo "gcc not found! Cloning to ${GCC_64_DIR}..."
    if ! git clone --depth=1 -b lineage-19.1 https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-android-4.9.git ${GCC_64_DIR}; then
        echo "Cloning failed! Aborting..."
        exit 1
    fi
fi

if ! [ -d "${GCC_32_DIR}" ]; then
    echo "gcc_32 not found! Cloning to ${GCC_32_DIR}..."
    if ! git clone --depth=1 -b lineage-19.1 https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_arm_arm-linux-androideabi-4.9.git ${GCC_32_DIR}; then
        echo "Cloning failed! Aborting..."
        exit 1
    fi
fi

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
make -j$(nproc --all) O=out ARCH=arm64 CC=clang LD=ld.lld AR=llvm-ar AS=llvm-as NM=llvm-nm OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip CROSS_COMPILE=$GCC_64_DIR/bin/aarch64-linux-android- CROSS_COMPILE_ARM32=$GCC_32_DIR/bin/arm-linux-androideabi- CLANG_TRIPLE=aarch64-linux-gnu- Image.gz-dtb dtbo.img

if [ -f "out/arch/arm64/boot/Image.gz-dtb" ] && [ -f "out/arch/arm64/boot/dtbo.img" ]; then
    echo -e "\nKernel compiled successfully! Zipping up...\n"
    if [ -d "$AK3_DIR" ]; then
        cp -r $AK3_DIR AnyKernel3
    elif ! git clone -q https://github.com/LeanxModulostk/AnyKernel3; then
        echo -e "\nAnyKernel3 repo not found locally and cloning failed! Aborting..."
        exit 1
    fi
    cp out/arch/arm64/boot/Image.gz-dtb AnyKernel3
    cp out/arch/arm64/boot/dtbo.img AnyKernel3
    rm -f *zip
    cd AnyKernel3
    git checkout ginkgo &> /dev/null
    zip -r9 "../$ZIPNAME" * -x '*.git*' README.md *placeholder
    cd ..
    rm -rf AnyKernel3
    rm -rf out/arch/arm64/boot
    echo -e "\nCompleted in $((SECONDS / 60)) minute(s) and $((SECONDS % 60)) second(s) !"
    echo "Zip: $ZIPNAME"
else
    echo -e "\nCompilation failed!"
    exit 1
fi
