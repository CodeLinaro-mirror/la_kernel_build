# Copyright (C) 2026 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Tests for kernel_modules_install check_dependencies attribute."""

load("//build/kernel/kleaf/impl:ddk/ddk_library.bzl", "ddk_library")
load("//build/kernel/kleaf/impl:ddk/ddk_module.bzl", "ddk_module")
load("//build/kernel/kleaf/impl:kernel_build.bzl", "kernel_build")
load("//build/kernel/kleaf/impl:kernel_module_group.bzl", "kernel_module_group")
load("//build/kernel/kleaf/impl:kernel_modules_install.bzl", "kernel_modules_install")
load("//build/kernel/kleaf/tests:failure_test.bzl", "failure_test")
load("//build/kernel/kleaf/tests:success_test.bzl", "success_test")

def kernel_modules_install_test(name):
    """Tests for kernel_modules_install check_dependencies.

    Args:
        name: name of the main test suite
    """

    # Test setup
    kernel_build(
        name = name + "_build",
        srcs = [],
        outs = [],
        make_goals = [],
        tags = ["manual"],
        pahole = "//build/kernel/kleaf/tests:fake_pahole",
    )

    # Module B
    ddk_module(
        name = name + "_b",
        out = name + "_b.ko",
        kernel_build = name + "_build",
        srcs = [],
        tags = ["manual"],
    )

    # Library
    ddk_library(
        name = name + "_lib",
        kernel_build = name + "_build",
        srcs = ["lib.c"],
        tags = ["manual"],
    )

    # Module A (depends on B and lib)
    ddk_module(
        name = name + "_a",
        out = name + "_a.ko",
        kernel_build = name + "_build",
        srcs = [],
        deps = [
            name + "_b",
            name + "_lib",
        ],
        tags = ["manual"],
    )

    # Group containing A (but not B)
    kernel_module_group(
        name = name + "_group_a",
        srcs = [name + "_a"],
        tags = ["manual"],
    )

    # Group containing both A and B
    kernel_module_group(
        name = name + "_group_ab",
        srcs = [
            name + "_a",
            name + "_b",
        ],
        tags = ["manual"],
    )

    # Compat test setup
    kernel_build(
        name = name + "_build_compat_a",
        srcs = [],
        outs = [],
        make_goals = [],
        tags = ["manual"],
        pahole = "//build/kernel/kleaf/tests:fake_pahole",
    )

    kernel_build(
        name = name + "_build_compat_b",
        base_kernel = name + "_build_compat_a",
        srcs = [],
        outs = [],
        make_goals = [],
        tags = ["manual"],
        pahole = "//build/kernel/kleaf/tests:fake_pahole",
    )

    ddk_module(
        name = name + "_module_compat_a",
        out = name + "_module_compat_a.ko",
        kernel_build = name + "_build_compat_a",
        srcs = [],
        tags = ["manual"],
    )

    ddk_module(
        name = name + "_module_compat_b",
        out = name + "_module_compat_b.ko",
        kernel_build = name + "_build_compat_b",
        srcs = [],
        tags = ["manual"],
    )

    tests = []

    # Test 1: check_dependencies = False (default). Should pass even if B is missing.
    kernel_modules_install(
        name = name + "_install_no_check",
        kernel_build = name + "_build",
        kernel_modules = [name + "_group_a"],
        tags = ["manual"],
    )
    success_test(
        name = name + "_test_no_check",
        target_under_test = name + "_install_no_check",
    )
    tests.append(name + "_test_no_check")

    # Test 2: check_dependencies = True, all deps installed. Should pass.
    kernel_modules_install(
        name = name + "_install_ok",
        kernel_build = name + "_build",
        kernel_modules = [name + "_group_ab"],
        check_dependencies = True,
        tags = ["manual"],
    )
    success_test(
        name = name + "_test_ok",
        target_under_test = name + "_install_ok",
    )
    tests.append(name + "_test_ok")

    # Test 3: check_dependencies = True, missing dep B. Should fail.
    kernel_modules_install(
        name = name + "_install_missing_dep",
        kernel_build = name + "_build",
        kernel_modules = [name + "_group_a"],
        check_dependencies = True,
        tags = ["manual"],
    )
    failure_test(
        name = name + "_test_missing_dep",
        target_under_test = name + "_install_missing_dep",
        error_message_substrs = [
            "The following modules are dependencies but are not installed",
            name + "_b",
        ],
    )
    tests.append(name + "_test_missing_dep")

    # Test 4: Explicitly use derived kernel. Should pass.
    kernel_modules_install(
        name = name + "_install_compat_derived",
        kernel_build = name + "_build_compat_b",
        kernel_modules = [
            name + "_module_compat_a",
            name + "_module_compat_b",
        ],
        tags = ["manual"],
    )
    success_test(
        name = name + "_test_compat_derived",
        target_under_test = name + "_install_compat_derived",
    )
    tests.append(name + "_test_compat_derived")

    # Test 5: Explicitly use base kernel. Should fail.
    kernel_modules_install(
        name = name + "_install_compat_base",
        kernel_build = name + "_build_compat_a",
        kernel_modules = [
            name + "_module_compat_a",
            name + "_module_compat_b",
        ],
        tags = ["manual"],
    )
    failure_test(
        name = name + "_test_compat_base",
        target_under_test = name + "_install_compat_base",
        error_message_substrs = ["They must refer to the same kernel_build."],
    )
    tests.append(name + "_test_compat_base")

    # Test 6: Inferred kernel. Should pass.
    kernel_modules_install(
        name = name + "_install_compat_inferred",
        kernel_modules = [
            name + "_module_compat_a",
            name + "_module_compat_b",
        ],
        tags = ["manual"],
    )
    success_test(
        name = name + "_test_compat_inferred",
        target_under_test = name + "_install_compat_inferred",
    )
    tests.append(name + "_test_compat_inferred")

    native.test_suite(
        name = name,
        tests = tests,
    )
