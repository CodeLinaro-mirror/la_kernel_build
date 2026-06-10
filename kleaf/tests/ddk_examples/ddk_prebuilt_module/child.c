/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Copyright (C) 2025 Google, Inc.
 *
 * This software is licensed under the terms of the GNU General Public
 * License version 2, as published by the Free Software Foundation, and
 * may be copied, distributed, and modified under those terms.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 */

#include <linux/module.h>
#include "parent.h"

void child_func(void);

void child_func(void) {
    parent_func();
}

EXPORT_SYMBOL(child_func);

MODULE_DESCRIPTION("A test module for DDK testing purposes");
MODULE_LICENSE("GPL v2");
MODULE_AUTHOR("Hong, Yifan <elsk@google.com>");
