// SPDX-License-Identifier: GPL-2.0
/*
 * Copyright (C) 2026 The Android Open Source Project
 */

#include <linux/module.h>
#include "lib_a.h"

static int __init child_init(void)
{
	lib_a_func();
	return 0;
}
module_init(child_init);

MODULE_DESCRIPTION("Child test module depending on ddk_library with ddk_module dep");
MODULE_AUTHOR("Android Kernel Team");
MODULE_LICENSE("GPL v2");
