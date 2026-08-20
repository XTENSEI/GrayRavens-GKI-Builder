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
ALLOWLIST="drivers/kernelsu/policy/allowlist.c"
if [ -f "$ALLOWLIST" ]; then
  sed -i 's/TWA_RESUME/true/g; s/TWA_NO_RESUME/false/g' "$ALLOWLIST"
  echo "ksun-54-compat: patched $ALLOWLIST for 5.4 task_work API"
fi
