// SPDX-License-Identifier: GPL-2.0
/*
 * Copyright (C) 2026 The Android Open Source Project
 */

#include <linux/module.h>
#include "lib_a.h"
#include "lib_b.h"

static int __init child_diamond_init(void)
{
	lib_a_func();
	lib_b_func();
	return 0;
}
module_init(child_diamond_init);

MODULE_DESCRIPTION("Child test module with diamond ddk_library dependencies");
MODULE_AUTHOR("Android Kernel Team");
MODULE_LICENSE("GPL v2");
