#!/bin/bash
# android12-5.10 GKI Kernel Build Script
set -e

# Error handler
trap 'echo "Build failed at line $LINENO. Exit code: $?" >&2' ERR

# ── Environment setup ────────────────────────────────────────────────
export ARCH=arm64
export LLVM=1
export LLVM_IAS=1
export PGO_INSTRUMENT=1
export KBUILD_BUILD_USER="JuanPrjktXiusegithubtobuildthis"
export KBUILD_BUILD_HOST="#StopRacist!"

# ── Clang toolchain check ────────────────────────────────────────────
if [ -z "$CLANG_PATH" ]; then
    echo "ERROR: CLANG_PATH is not set. Build aborted." >&2
    exit 1
fi

if [ ! -x "$CLANG_PATH/bin/clang" ]; then
    echo "ERROR: clang not found in $CLANG_PATH/bin" >&2
    exit 1
fi

export PATH="${CLANG_PATH}/bin:${PATH}"

echo "Using toolchain : ${CLANG_VARIANT:-unknown}"
echo "Toolchain path  : $CLANG_PATH"
echo "Clang version   : $("$CLANG_PATH/bin/clang" --version | head -n1)"

# ── Compiler string ───────────────────────────────────────────────────
case "${CLANG_VARIANT}" in
    NEUTRON_19)
        export KBUILD_COMPILER_STRING="Neutron Clang 19.0.0 +PGO +BOLT +Polly +ThinLTO +O3"
        ;;
    ZYC_12)
        export KBUILD_COMPILER_STRING="ZYC Clang 12.0.0 +ThinLTO +O3"
        ;;
    AOSP_12)
        export KBUILD_COMPILER_STRING="AOSP Clang r445002 (LLVM 12.0.5)"
        ;;
    YUKI_23)
        export KBUILD_COMPILER_STRING="Yuki Clang 23 +BOLT +ThinLTO +O3"
        ;;
    *)
        export KBUILD_COMPILER_STRING="Unknown Clang"
        ;;
esac

echo "Compiler string : $KBUILD_COMPILER_STRING"

# ── KCFLAGS ───────────────────────────────────────────────────────────
export KCFLAGS="-w -march=armv8.2-a -mtune=cortex-a55"

# ── NTSYNC SELinux injection ─────────────────────────────────────────
RULES_FILE="drivers/kernelsu/selinux/rules.c"

if [ -f "$RULES_FILE" ]; then
    echo "Injecting NTSYNC SELinux rules..."

    sed -i '/rcu_assign_pointer(selinux_state.policy, pol);/i \
    // NTSYNC SEPol rules\n\
    ksu_allow(db, "kernel", "device", "chr_file", "setattr");\n\
    ksu_allow(db, "kernel", "device", "chr_file", "relabelfrom");\n\
    ksu_allow(db, "kernel", "gpu_device", "chr_file", "relabelto");\n\
    ksu_allow(db, "kernel", "gpu_device", "chr_file", "setattr");\n\
\n\
    ksu_allow(db, "untrusted_app", "gpu_device", "chr_file", "read");\n\
    ksu_allow(db, "untrusted_app", "gpu_device", "chr_file", "write");\n\
    ksu_allow(db, "untrusted_app", "gpu_device", "chr_file", "open");\n\
    ksu_allow(db, "untrusted_app", "gpu_device", "chr_file", "ioctl");\n\
    ksu_allow(db, "untrusted_app", "gpu_device", "chr_file", "map");\n' \
    "$RULES_FILE"

    echo "SELinux rules injected."
else
    echo "KernelSU rules.c not found, skipping injection."
fi

# ── Generate config ──────────────────────────────────────────────────
echo "Generating GKI defconfig..."
make O=out gki_defconfig

# ── LTO config ───────────────────────────────────────────────────────
echo "Configuring THIN LTO..."

scripts/config --file out/.config \
    -e LTO_CLANG \
    -d LTO_NONE \
    -e LTO_CLANG_THIN \
    -d LTO_CLANG_FULL

# ── Build kernel ─────────────────────────────────────────────────────
echo "Building kernel..."
make -j"$(nproc --all)" O=out Image

# ── KMI validation ───────────────────────────────────────────────────
echo "Running KMI validation..."
python3 KMI_function_symbols_test.py || true

echo "Build completed successfully!"
echo "Toolchain used: ${CLANG_VARIANT}"
