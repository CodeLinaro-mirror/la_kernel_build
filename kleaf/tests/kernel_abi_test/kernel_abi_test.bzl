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

"""Tests for `kernel_abi` and symbol list management behaviour."""

load("//build/kernel/kleaf/impl:abi/get_src_kmi_symbol_list.bzl", "get_src_kmi_symbol_list")
load("//build/kernel/kleaf/impl:kernel_build.bzl", "kernel_build")
load("//build/kernel/kleaf/tests:failure_test.bzl", "failure_test")

def kernel_abi_test(name):
    """Defines tests for ABI extraction, symbol lists, and ABI tracking.

    Args:
        name: Name of the test suite.
    """
    tests = []

    symbols_build = name + "_symbols_build"
    kernel_build(
        name = symbols_build,
        srcs = [],
        outs = ["vmlinux"],
        additional_kmi_symbol_lists = ["fake_symbol_list_base"],
        collect_unstripped_modules = True,
        keep_module_symvers = True,
        kmi_symbol_list = None,
        kmi_symbol_list_strict_mode = True,
        make_goals = [],
        pahole = "//build/kernel/kleaf/tests:fake_pahole",
        trim_nonlisted_kmi = True,
        tags = ["manual"],
    )

    # Defensive check: get_src_kmi_symbol_list fails clearly if kmi_symbol_list is unset.
    get_src_kmi_symbol_list(
        name = name + "_missing_src_kmi_symbol_list",
        kernel_build = symbols_build,
        tags = ["manual"],
    )
    failure_test(
        name = name + "_missing_src_kmi_symbol_list_fail_test",
        target_under_test = name + "_missing_src_kmi_symbol_list",
        error_message_substrs = ["does not specify kmi_symbol_list"],
    )
    tests.append(name + "_missing_src_kmi_symbol_list_fail_test")

    native.test_suite(
        name = name,
        tests = tests,
    )
