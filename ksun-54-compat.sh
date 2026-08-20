#!/bin/bash
# ksun-54-compat.sh — Patch KSUN pkg_observer.c for Linux 5.4
set -e

FILE="drivers/kernelsu/manager/pkg_observer.c"

if [ ! -f "$FILE" ]; then
  echo "ksun-54-compat: $FILE not found, skipping"
  exit 0
fi

# Save everything from add_mark_on_inode onwards (the unchanged part)
REST=$(sed -n '/^static int add_mark_on_inode/,$p' "$FILE")

cat > "$FILE" << 'ENDOFFILE'
// SPDX-License-Identifier: GPL-2.0
// Patched for Linux 5.4 compat
#include <linux/module.h>
#include <linux/fs.h>
#include <linux/namei.h>
#include <linux/fsnotify_backend.h>
#include <linux/slab.h>
#include <linux/rculist.h>
#include <linux/version.h>
#include "klog.h" // IWYU pragma: keep
#include "manager/throne_tracker.h"

#define MASK_SYSTEM (FS_CREATE | FS_MOVE | FS_EVENT_ON_CHILD)

struct watch_dir {
	const char *path;
	u32 mask;
	struct path kpath;
	struct inode *inode;
	struct fsnotify_mark *mark;
};

static struct fsnotify_group *g;

static void ksu_handle_packages(u32 mask, const struct qstr *name)
{
	if (!name)
		return;
	if (mask & FS_ISDIR)
		return;
	if (name->len == 13 && !memcmp(name->name, "packages.list", 13)) {
		pr_info("packages.list detected: %d\n", mask);
		track_throne(false);
	}
}

#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 10, 0)
static int ksu_handle_inode_event(struct fsnotify_mark *mark, u32 mask,
				  struct inode *inode, struct inode *dir,
				  const struct qstr *file_name, u32 cookie)
{
	ksu_handle_packages(mask, file_name);
	return 0;
}
static const struct fsnotify_ops ksu_ops = {
	.handle_inode_event = ksu_handle_inode_event,
};
#else
static int ksu_handle_event(struct fsnotify_group *group, u32 mask,
			    const void *data, int data_type,
			    struct inode *dir, const struct qstr *name,
			    u32 cookie)
{
	ksu_handle_packages(mask, name);
	return 0;
}
static const struct fsnotify_ops ksu_ops = {
	.handle_event = ksu_handle_event,
};
#endif

ENDOFFILE

echo "$REST" >> "$FILE"
echo "ksun-54-compat: patched $FILE for 5.4 fsnotify API"

# --- Fix 2: TWA_RESUME not available in 5.4 ---
# In 5.4, task_work_add() takes a bool, not enum task_work_notify_mode.
# TWA_RESUME = true, TWA_NO_RESUME = false
for f in drivers/kernelsu/policy/allowlist.c drivers/kernelsu/supercall/supercall.c; do
  if [ -f "$f" ]; then
    sed -i 's/TWA_RESUME/true/g; s/TWA_NO_RESUME/false/g' "$f"
    echo "ksun-54-compat: patched $f for 5.4 task_work API"
  fi
done

# --- Fix 3: filter_count not in 5.4 struct seccomp ---
# 5.4 seccomp struct only has mode + filter pointer, no filter_count.
for f in drivers/kernelsu/policy/allowlist.c drivers/kernelsu/policy/app_profile.c drivers/kernelsu/supercall/supercall.c; do
  if [ -f "$f" ]; then
    sed -i '/atomic_set.*filter_count/d' "$f"
    echo "ksun-54-compat: patched $f for 5.4 seccomp struct"
  fi
done

# --- Fix 4: linux/minmax.h missing in 5.4 ---
# min/max macros are in linux/kernel.h on 5.4.
SULOG="drivers/kernelsu/sulog/event.c"
if [ -f "$SULOG" ]; then
  sed -i '/#include <linux\/minmax.h>/d' "$SULOG"
  echo "ksun-54-compat: patched $SULOG for 5.4 minmax.h"
fi

# --- Fix 5: selinux_state.policy does not exist in 5.4 ---
# 5.4 struct selinux_state has .ss and .avc but no .policy or .policy_mutex.
# KSUN's rules.c heavily manipulates selinux_policy internals.
# Stub it out on 5.4 -- KSU root works, per-app SELinux profiles disabled.
RULES="drivers/kernelsu/selinux/rules.c"
if [ -f "$RULES" ]; then
  cat > "$RULES" << 'ENDRULES'
// SPDX-License-Identifier: GPL-2.0
// Stubbed for Linux 5.4 -- selinux_state.policy does not exist.
#include <linux/types.h>
#include <linux/version.h>
#include "klog.h"

struct selinux_policy;
struct selinux_policy *backup_sepolicy;

void apply_kernelsu_rules(void)
{
	pr_info("ksu: sepolicy rules disabled on 5.4 (incompatible internals)");
}

int handle_sepolicy(void __user *user_data, u64 data_len)
{
	pr_warn("ksu: sepolicy not supported on 5.4");
	return -ENOSYS;
}
ENDRULES
  echo "ksun-54-compat: stubbed $RULES for 5.4"
fi

# --- Fix 6: sepolicy.c uses deep selinux_policy internals ---
# filename_trans_key, filename_trans_datum, selinux_policy layout all changed.
# Since rules.c is stubbed, sepolicy.c is never called. Stub it.
SEPOLICY="drivers/kernelsu/selinux/sepolicy.c"
if [ -f "$SEPOLICY" ]; then
  cat > "$SEPOLICY" << 'ENDSEPOL'
// SPDX-License-Identifier: GPL-2.0
// Stubbed for Linux 5.4 -- selinux_policy internals incompatible.
#include <linux/types.h>
#include "ss/policydb.h"

struct selinux_policy;

struct selinux_policy *ksu_dup_sepolicy(struct selinux_policy *old_pol)
{
	return ERR_PTR(-ENOSYS);
}
void ksu_destroy_sepolicy(struct selinux_policy *orig) { }
bool ksu_type(struct policydb *db, const char *n, const char *a) { return false; }
bool ksu_attribute(struct policydb *db, const char *n) { return false; }
bool ksu_permissive(struct policydb *db, const char *t) { return false; }
bool ksu_enforce(struct policydb *db, const char *t) { return false; }
bool ksu_typeattribute(struct policydb *db, const char *t, const char *a) { return false; }
bool ksu_exists(struct policydb *db, const char *n) { return false; }
bool ksu_allow(struct policydb *db, const char *s, const char *t, const char *c, const char *p) { return false; }
bool ksu_deny(struct policydb *db, const char *s, const char *t, const char *c, const char *p) { return false; }
bool ksu_auditallow(struct policydb *db, const char *s, const char *t, const char *c, const char *p) { return false; }
bool ksu_dontaudit(struct policydb *db, const char *s, const char *t, const char *c, const char *p) { return false; }
bool ksu_allowxperm(struct policydb *db, const char *s, const char *t, const char *c, const char *r) { return false; }
bool ksu_auditallowxperm(struct policydb *db, const char *s, const char *t, const char *c, const char *r) { return false; }
bool ksu_dontauditxperm(struct policydb *db, const char *s, const char *t, const char *c, const char *r) { return false; }
bool ksu_type_transition(struct policydb *db, const char *s, const char *t, const char *c, const char *d, const char *o) { return false; }
bool ksu_type_change(struct policydb *db, const char *s, const char *t, const char *c, const char *d) { return false; }
bool ksu_type_member(struct policydb *db, const char *s, const char *t, const char *c, const char *d) { return false; }
bool ksu_genfscon(struct policydb *db, const char *fn, const char *p, const char *c) { return false; }
ENDSEPOL
  echo "ksun-54-compat: stubbed $SEPOLICY for 5.4"
fi

# --- Fix 7: dispatch.c needs sched/task.h for tasklist_lock + init_task ---
# In 5.4, tasklist_lock and init_task are declared in sched/task.h,
# not auto-included by sched.h.
DISPATCH="drivers/kernelsu/supercall/dispatch.c"
if [ -f "$DISPATCH" ]; then
  sed -i '/#include <linux\/capability.h>/a #include <linux/sched/task.h>' "$DISPATCH"
  echo "ksun-54-compat: patched $DISPATCH for 5.4 tasklist_lock"
fi
