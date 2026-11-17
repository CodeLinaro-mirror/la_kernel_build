// SPDX-License-Identifier: GPL-2.0
/*
 * Copyright (C) 2026 The Android Open Source Project
 */

#include <linux/module.h>
#include "parent.h"

void parent_func(void)
{
}
EXPORT_SYMBOL_GPL(parent_func);

MODULE_DESCRIPTION("Parent test module exporting a symbol for ddk_library tests");
MODULE_AUTHOR("Android Kernel Team");
MODULE_LICENSE("GPL v2");
