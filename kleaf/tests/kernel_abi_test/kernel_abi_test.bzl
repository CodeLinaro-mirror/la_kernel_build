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

load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts", "unittest")
load("//build/kernel/kleaf/impl:abi/get_src_kmi_symbol_list.bzl", "get_src_kmi_symbol_list")
load("//build/kernel/kleaf/impl:abi/kernel_abi.bzl", "kernel_abi")
load("//build/kernel/kleaf/impl:common_providers.bzl", "KernelBuildAbiInfo")
load("//build/kernel/kleaf/impl:kernel_build.bzl", "kernel_build")
load("//build/kernel/kleaf/tests:failure_test.bzl", "failure_test")
load("//build/kernel/kleaf/tests:test_utils.bzl", "test_utils")

def _target_presence_test_impl(ctx):
    env = unittest.begin(ctx)
    asserts.equals(
        env,
        ctx.attr.expected,
        ctx.attr.actual,
        "target {} existence mismatch".format(ctx.attr.target_name),
    )
    return unittest.end(env)

_target_presence_test = unittest.make(
    impl = _target_presence_test_impl,
    attrs = {
        "target_name": attr.string(mandatory = True),
        "actual": attr.bool(mandatory = True),
        "expected": attr.bool(mandatory = True),
    },
)

def _add_target_presence_test(tests, target_name, expected):
    test_name = "{}_presence_test".format(target_name)
    _target_presence_test(
        name = test_name,
        target_name = target_name,
        actual = native.existing_rule(target_name) != None,
        expected = expected,
    )
    tests.append(test_name)

def _kernel_build_abi_info_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)
    abi_info = target[KernelBuildAbiInfo]

    asserts.equals(
        env,
        ctx.attr.expect_combined_symbol_list,
        abi_info.combined_abi_symbollist != None,
        "combined_abi_symbollist presence mismatch for {}".format(target.label),
    )
    asserts.equals(
        env,
        ctx.attr.expect_src_symbol_list,
        abi_info.src_kmi_symbol_list != None,
        "src_kmi_symbol_list presence mismatch for {}".format(target.label),
    )
    asserts.equals(
        env,
        ctx.attr.expect_strict_mode_out,
        abi_info.kmi_strict_mode_out != None,
        "kmi_strict_mode_out presence mismatch for {}".format(target.label),
    )
    asserts.equals(
        env,
        ctx.attr.expect_trim,
        bool(abi_info.trim_nonlisted_kmi),
        "trim_nonlisted_kmi mismatch for {}".format(target.label),
    )
    return analysistest.end(env)

_kernel_build_abi_info_test = analysistest.make(
    impl = _kernel_build_abi_info_test_impl,
    attrs = {
        "expect_combined_symbol_list": attr.bool(mandatory = True),
        "expect_src_symbol_list": attr.bool(mandatory = True),
        "expect_strict_mode_out": attr.bool(mandatory = True),
        "expect_trim": attr.bool(mandatory = True),
    },
)

def _abi_dump_filtering_test_impl(ctx):
    env = analysistest.begin(ctx)
    action = test_utils.find_action(env, "AbiDumpFilteredStg")
    script = test_utils.get_shell_script(env, action)
    asserts.equals(
        env,
        ctx.attr.expect_filtered,
        "--symbols :" in script,
        "AbiDumpFilteredStg filtering mismatch in script:\n{}".format(script),
    )
    return analysistest.end(env)

_abi_dump_filtering_test = analysistest.make(
    impl = _abi_dump_filtering_test_impl,
    attrs = {
        "expect_filtered": attr.bool(mandatory = True),
    },
)

def _nodiff_update_test_impl(ctx):
    env = analysistest.begin(ctx)
    target = analysistest.target_under_test(env)
    runfiles = [f.basename for f in target[DefaultInfo].default_runfiles.files.to_list()]
    asserts.equals(
        env,
        ctx.attr.expect_strict_mode_check,
        # Matches basename created by _kmi_symbol_list_strict_mode in kernel_build.bzl.
        "kmi_symbol_list_strict_mode_checked" in runfiles,
        "kmi_symbol_list_strict_mode_checked mismatch in runfiles: {}".format(runfiles),
    )
    return analysistest.end(env)

_nodiff_update_test = analysistest.make(
    impl = _nodiff_update_test_impl,
    attrs = {
        "expect_strict_mode_check": attr.bool(mandatory = True),
    },
)

def _analyse_ok_test_impl(ctx):
    env = analysistest.begin(ctx)
    return analysistest.end(env)

_analyse_ok_test = analysistest.make(
    impl = _analyse_ok_test_impl,
)

def kernel_abi_test(name):
    """Defines tests for ABI extraction, symbol lists, and ABI tracking.

    Args:
        name: Name of the test suite.
    """
    tests = []

    # Extraction only: neither symbol lists nor abi_definition_stg (e.g. android-mainline).
    no_symbols_build = name + "_no_symbols_build"
    extract_only_abi = name + "_extract_only_abi"
    kernel_build(
        name = no_symbols_build,
        srcs = [],
        outs = ["vmlinux"],
        collect_unstripped_modules = True,
        keep_module_symvers = True,
        make_goals = [],
        pahole = "//build/kernel/kleaf/tests:fake_pahole",
        tags = ["manual"],
    )
    kernel_abi(
        name = extract_only_abi,
        kernel_build = no_symbols_build,
        define_abi_targets = False,
        enable_add_vmlinux = False,
        tags = ["manual"],
    )
    _kernel_build_abi_info_test(
        name = name + "_extract_only_abi_info_test",
        target_under_test = no_symbols_build,
        expect_combined_symbol_list = False,
        expect_src_symbol_list = False,
        expect_strict_mode_out = False,
        expect_trim = False,
    )
    tests.append(name + "_extract_only_abi_info_test")
    _abi_dump_filtering_test(
        name = name + "_extract_only_dump_unfiltered_test",
        target_under_test = extract_only_abi + "_dump",
        expect_filtered = False,
    )
    tests.append(name + "_extract_only_dump_unfiltered_test")
    failure_test(
        name = name + "_extract_only_update_fail_test",
        target_under_test = extract_only_abi + "_update",
        error_message_substrs = ["and other ABI targets are not setup"],
    )
    tests.append(name + "_extract_only_update_fail_test")
    for suffix, expected in (
        ("_dump", True),
        ("_diff_executable", True),
        ("_update", True),
        ("_diff", False),
        ("_nodiff_update", False),
        ("_update_symbol_list", False),
        ("_extracted_symbols", False),
        ("_src_kmi_symbol_list", False),
        ("_diff_symbol_list", False),
    ):
        _add_target_presence_test(tests, extract_only_abi + suffix, expected)

    # Symbol lists without baseline tracking: filtered ABI dump, no committed abi.stg.
    symbols_build = name + "_symbols_build"
    symbols_only_abi = name + "_symbols_only_abi"
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
    kernel_abi(
        name = symbols_only_abi,
        kernel_build = symbols_build,
        define_abi_targets = False,
        enable_add_vmlinux = False,
        tags = ["manual"],
    )
    _kernel_build_abi_info_test(
        name = name + "_symbols_only_abi_info_test",
        target_under_test = symbols_build,
        expect_combined_symbol_list = True,
        expect_src_symbol_list = False,
        expect_strict_mode_out = True,
        expect_trim = True,
    )
    tests.append(name + "_symbols_only_abi_info_test")
    _abi_dump_filtering_test(
        name = name + "_symbols_only_dump_filtered_test",
        target_under_test = symbols_only_abi + "_dump",
        expect_filtered = True,
    )
    tests.append(name + "_symbols_only_dump_filtered_test")
    failure_test(
        name = name + "_symbols_only_update_fail_test",
        target_under_test = symbols_only_abi + "_update",
        error_message_substrs = ["and other ABI targets are not setup"],
    )
    tests.append(name + "_symbols_only_update_fail_test")
    for suffix, expected in (
        ("_dump", True),
        ("_diff_executable", True),
        ("_update", True),
        ("_diff", False),
        ("_nodiff_update", False),
        ("_update_symbol_list", False),
        ("_extracted_symbols", False),
        ("_src_kmi_symbol_list", False),
        ("_diff_symbol_list", False),
    ):
        _add_target_presence_test(tests, symbols_only_abi + suffix, expected)

    # Device / DDK symbol list update (e.g. virtual_device, db845c, out-of-tree DDK modules).
    dev_build = name + "_device_build"
    dev_abi = name + "_device_abi"
    kernel_build(
        name = dev_build,
        srcs = [],
        base_kernel = symbols_build,
        outs = [],
        collect_unstripped_modules = True,
        kmi_symbol_list = "fake_symbol_list_device",
        make_goals = [],
        pahole = "//build/kernel/kleaf/tests:fake_pahole",
        tags = ["manual"],
    )
    kernel_abi(
        name = dev_abi,
        kernel_build = dev_build,
        kmi_symbol_list_add_only = True,
        tags = ["manual"],
    )
    _analyse_ok_test(
        name = name + "_device_update_symbol_list_analyse_test",
        target_under_test = dev_abi + "_update_symbol_list",
    )
    tests.append(name + "_device_update_symbol_list_analyse_test")
    for suffix, expected in (
        ("_src_kmi_symbol_list", True),
        ("_extracted_symbols", True),
        ("_update_symbol_list", True),
        ("_diff_symbol_list", False),
    ):
        _add_target_presence_test(tests, dev_abi + suffix, expected)

    # Standalone target with both kmi_symbol_list and abi_definition_stg: verifies
    # _diff_symbol_list is no longer created even when abi_definition_stg is set.
    kmi_stg_build = name + "_kmi_stg_build"
    kmi_stg_abi = name + "_kmi_stg_abi"
    kernel_build(
        name = kmi_stg_build,
        srcs = [],
        outs = ["vmlinux"],
        collect_unstripped_modules = True,
        keep_module_symvers = True,
        kmi_symbol_list = "fake_symbol_list_base",
        kmi_symbol_list_strict_mode = True,
        make_goals = [],
        pahole = "//build/kernel/kleaf/tests:fake_pahole",
        tags = ["manual"],
    )
    kernel_abi(
        name = kmi_stg_abi,
        kernel_build = kmi_stg_build,
        abi_definition_stg = "fake_abi.stg",
        enable_add_vmlinux = False,
        tags = ["manual"],
    )
    _nodiff_update_test(
        name = name + "_kmi_stg_nodiff_update_test",
        target_under_test = kmi_stg_abi + "_nodiff_update",
        expect_strict_mode_check = True,
    )
    tests.append(name + "_kmi_stg_nodiff_update_test")
    _analyse_ok_test(
        name = name + "_kmi_stg_update_analyse_test",
        target_under_test = kmi_stg_abi + "_update",
    )
    tests.append(name + "_kmi_stg_update_analyse_test")
    for suffix, expected in (
        ("_src_kmi_symbol_list", True),
        ("_extracted_symbols", True),
        ("_update_symbol_list", True),
        ("_kmi_symbol_checks", True),
        ("_nodiff_update", True),
        ("_update", True),
        ("_diff_symbol_list", False),
    ):
        _add_target_presence_test(tests, kmi_stg_abi + suffix, expected)

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
