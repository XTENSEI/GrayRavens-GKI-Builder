#!/usr/bin/env bash
# selinux.sh
# SELinux rule injections, sourced by build.sh from inside $KSRC
# Author: GrayRavens Team

SELINUX_RULES_C="drivers/kernelsu/selinux/rules.c"

# Sanity check: skip if KernelSU isn't installed (VNL builds have no KSU tree).
if [[ ! -f "$SELINUX_RULES_C" ]]; then
    echo "selinux.sh: $SELINUX_RULES_C not found (VNL build?), OPLUS rules NOT injected."
    return 0
fi

sites_before=$(grep -c 'GrayRavens: .* SELinux rules applied' "$SELINUX_RULES_C" || true)

inject_selinux() {
    local label="$1"
    local rules="$2"
    local mark
    # the pr_info marks the site so dmesg tells us whether the block ran.
    # printf keeps a real backslash-n in the C string; sed eats a bare \n.
    mark=$(printf 'pr_info("GrayRavens: %s SELinux rules applied\\\\n");' "$label")
    echo "Injecting ${label} SELinux rules..."
    sed -i "/rcu_assign_pointer(selinux_state.policy, pol);/i ${mark}\\
${rules}" \
        "$SELINUX_RULES_C"
}

# NTSYNC: kernel worker chmods and relabels /dev/ntsync, untrusted_app uses it.
inject_selinux "NTSYNC" \
' ksu_allow(db, "kernel", "device", "chr_file", "setattr");\
ksu_allow(db, "kernel", "device", "chr_file", "relabelfrom");\
ksu_allow(db, "kernel", "gpu_device", "chr_file", "relabelto");\
ksu_allow(db, "kernel", "gpu_device", "chr_file", "setattr");\
ksu_allow(db, "untrusted_app", "gpu_device", "chr_file", "read");\
ksu_allow(db, "untrusted_app", "gpu_device", "chr_file", "write");\
ksu_allow(db, "untrusted_app", "gpu_device", "chr_file", "open");\
ksu_allow(db, "untrusted_app", "gpu_device", "chr_file", "ioctl");\
ksu_allow(db, "untrusted_app", "gpu_device", "chr_file", "map");\
'

# sched_assist: nodes carry the generic proc type, writers are denied under enforcing.
inject_selinux "OPLUS sched_assist" \
' ksu_allow(db, "system_server", "proc", "file", "ioctl");\
ksu_allow(db, "system_server", "proc", "file", "write");\
ksu_allow(db, "priv_app", "proc", "file", "write");\
ksu_allow(db, "platform_app", "proc", "file", "write");\
ksu_allow(db, "untrusted_app", "proc", "file", "write");\
ksu_allow(db, "hal_allocator_default", "proc", "file", "write");\
ksu_allowxperm(db, "system_server", "proc", "file", "2700-2701");\
ksu_allowxperm(db, "priv_app", "proc", "file", "2700-2701");\
ksu_allowxperm(db, "platform_app", "proc", "file", "2700-2701");\
'

# nandswap: vendor service creates /data/nandswap/swapfile, drives /proc/nandswap.
inject_selinux "OPLUS nandswap" \
' ksu_allow(db, "nandswap", "nandswap_proc", "dir", "search");\
ksu_allow(db, "nandswap", "nandswap_proc", "file", "open");\
ksu_allow(db, "nandswap", "nandswap_proc", "file", "read");\
ksu_allow(db, "nandswap", "nandswap_proc", "file", "write");\
ksu_allow(db, "nandswap", "nandswap_proc", "file", "getattr");\
ksu_allow(db, "nandswap", "nandswap_file", "dir", "create");\
ksu_allow(db, "nandswap", "nandswap_file", "dir", "search");\
ksu_allow(db, "nandswap", "nandswap_file", "dir", "write");\
ksu_allow(db, "nandswap", "nandswap_file", "dir", "add_name");\
ksu_allow(db, "nandswap", "nandswap_file", "file", "create");\
ksu_allow(db, "nandswap", "nandswap_file", "file", "open");\
ksu_allow(db, "nandswap", "nandswap_file", "file", "read");\
ksu_allow(db, "nandswap", "nandswap_file", "file", "write");\
ksu_allow(db, "nandswap", "nandswap_file", "file", "getattr");\
ksu_allow(db, "nandswap", "nandswap_file", "file", "setattr");\
ksu_allow(db, "init", "nandswap_file", "dir", "create");\
ksu_allow(db, "init", "nandswap_file", "dir", "search");\
ksu_allow(db, "init", "nandswap_file", "dir", "write");\
ksu_allow(db, "init", "nandswap_file", "dir", "add_name");\
ksu_allow(db, "vendor_init", "nandswap_file", "dir", "create");\
ksu_allow(db, "vendor_init", "nandswap_file", "dir", "search");\
'

# The sed above rewrites two apply sites. If KernelSU moves them, skip nothing
# silently: a green build that ships no rules is the bug we are fixing.
sites_after=$(grep -c 'GrayRavens: .* SELinux rules applied' "$SELINUX_RULES_C" || true)
if [ "${sites_after:-0}" -le "${sites_before:-0}" ]; then
    echo "FATAL: selinux.sh: rules did not land in $SELINUX_RULES_C" >&2
    echo "       the KSU apply hook changed, update the sed pattern" >&2
    exit 1
fi
echo "selinux.sh: OPLUS rules injected at ${sites_after} apply site(s)"
