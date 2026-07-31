#!/usr/bin/env bash
# selinux.sh
# SELinux rule injections for GrayRavens Vindicator drivers + NTSYNC
# Sourced by build.sh — must be called from inside $KSRC
# Author: GrayRavens Team

SELINUX_RULES_C="drivers/kernelsu/selinux/rules.c"

# Sanity check — gracefully skip if KernelSU isn't installed
if [[ ! -f "$SELINUX_RULES_C" ]]; then
    echo "selinux.sh: $SELINUX_RULES_C not found — KernelSU not installed, skipping SELinux injection."
    return 0
fi

inject_selinux() {
    local label="$1"
    local rules="$2"
    echo "Injecting ${label} SELinux rules..."
    sed -i "/rcu_assign_pointer(selinux_state.policy, pol);/i ${rules}" \
        "$SELINUX_RULES_C"
}

# ---------------------------------------------------------------------------
# NTSYNC — Allow kernel worker to chmod and relabel /dev/ntsync
#         Allow Winlator (untrusted_app) to use /dev/ntsync
# ---------------------------------------------------------------------------
inject_selinux "NTSYNC" \
' ksu_allow(db, "kernel", "device", "chr_file", "setattr");\n\
ksu_allow(db, "kernel", "device", "chr_file", "relabelfrom");\n\
ksu_allow(db, "kernel", "gpu_device", "chr_file", "relabelto");\n\
ksu_allow(db, "kernel", "gpu_device", "chr_file", "setattr");\n\
ksu_allow(db, "untrusted_app", "gpu_device", "chr_file", "read");\n\
ksu_allow(db, "untrusted_app", "gpu_device", "chr_file", "write");\n\
ksu_allow(db, "untrusted_app", "gpu_device", "chr_file", "open");\n\
ksu_allow(db, "untrusted_app", "gpu_device", "chr_file", "ioctl");\n\
ksu_allow(db, "untrusted_app", "gpu_device", "chr_file", "map");\n'

# ---------------------------------------------------------------------------
# Iyashi / Kasumi — thermal performance management
# Iyashi relaxes cooling device targets to hold a performance floor.
# Kasumi dampens thermal_zone_get_temp() readings by a configurable offset.
# Both read/write thermal zone sysfs nodes.
# ---------------------------------------------------------------------------
inject_selinux "Iyashi / Kasumi" \
' ksu_allow(db, "kernel", "sysfs_therm", "dir", "search");\n\
ksu_allow(db, "kernel", "sysfs_therm", "file", "read");\n\
ksu_allow(db, "kernel", "sysfs_therm", "file", "write");\n\
ksu_allow(db, "kernel", "sysfs_therm", "file", "open");\n'
