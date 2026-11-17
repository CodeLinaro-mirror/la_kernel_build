// SPDX-License-Identifier: GPL-2.0
/*
 * Copyright (C) 2026 The Android Open Source Project
 */

#include <linux/module.h>
#include "lib_a.h"
#include "parent.h"

static int __init child_with_parent_init(void)
{
	parent_func();
	lib_a_func();
	return 0;
}
module_init(child_with_parent_init);

MODULE_DESCRIPTION("Child test module depending on both parent module and ddk_library");
MODULE_AUTHOR("Android Kernel Team");
MODULE_LICENSE("GPL v2");
