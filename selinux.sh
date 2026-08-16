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
# Selene - game detection reads /proc/<pid>/cmdline + /data/misc/selene list
# ---------------------------------------------------------------------------
inject_selinux "Selene" \
' ksu_allow(db, "kernel", "proc_pid_cmdline", "file", "read");\n\
ksu_allow(db, "kernel", "proc_pid_cmdline", "file", "open");\n\
ksu_allow(db, "kernel", "proc_pid_cmdline", "file", "getattr");\n\
ksu_allow(db, "kernel", "misc_file", "dir", "search");\n\
ksu_allow(db, "kernel", "misc_file", "file", "read");\n\
ksu_allow(db, "kernel", "misc_file", "file", "open");\n\
ksu_allow(db, "kernel", "misc_file", "file", "getattr");\n'

# ---------------------------------------------------------------------------
# Zenith - tunable dir under /sys/devices/system/cpu/cpufreq (sysfs_devices_system_cpu)
# ---------------------------------------------------------------------------
inject_selinux "Zenith cpufreq sysfs" \
' ksu_allow(db, "kernel", "sysfs_devices_system_cpu", "dir", "search");\n\
ksu_allow(db, "kernel", "sysfs_devices_system_cpu", "dir", "getattr");\n\
ksu_allow(db, "kernel", "sysfs_devices_system_cpu", "file", "read");\n\
ksu_allow(db, "kernel", "sysfs_devices_system_cpu", "file", "write");\n\
ksu_allow(db, "kernel", "sysfs_devices_system_cpu", "file", "open");\n\
ksu_allow(db, "kernel", "sysfs_devices_system_cpu", "file", "getattr");\n'
