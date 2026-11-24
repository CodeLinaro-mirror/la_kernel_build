# Copyright (C) 2022 The Android Open Source Project
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

"""Tests for `ddk_module`."""

load("@bazel_skylib//lib:sets.bzl", "sets")
load("@bazel_skylib//lib:unittest.bzl", "analysistest", "asserts")
load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("@bazel_skylib//rules:diff_test.bzl", "diff_test")
load("@bazel_skylib//rules:write_file.bzl", "write_file")
load(
    "//build/kernel/kleaf/impl:common_providers.bzl",
    "ModuleSymversFileInfo",
    "ModuleSymversInfo",
)
load("//build/kernel/kleaf/impl:ddk/ddk_headers.bzl", "ddk_headers")
load("//build/kernel/kleaf/impl:ddk/ddk_library.bzl", "ddk_library")
load("//build/kernel/kleaf/impl:ddk/ddk_module.bzl", "ddk_module")
load("//build/kernel/kleaf/impl:ddk/ddk_submodule.bzl", "ddk_submodule")
load("//build/kernel/kleaf/impl:kernel_build.bzl", "kernel_build")
load("//build/kernel/kleaf/impl:kernel_module.bzl", "kernel_module")
load("//build/kernel/kleaf/impl:kernel_module_group.bzl", "kernel_module_group")
load("//build/kernel/kleaf/tests:failure_test.bzl", "failure_test")
load("//build/kernel/kleaf/tests/utils:contain_lines_test.bzl", "contain_lines_test")
load("//build/kernel/kleaf/tests/utils:output_group_files.bzl", "output_group_files")
load(":ddk_headers_test.bzl", "check_ddk_headers_info")
load(":makefiles_test.bzl", "get_top_level_file")

def _ddk_module_test_impl(ctx):
    env = analysistest.begin(ctx)

    target_under_test = analysistest.target_under_test(env)

    entries = target_under_test[ModuleSymversInfo].entries.to_list()
    asserts.equals(
        env,
        1,
        len(entries),
        "{} has multiple Module.symvers, expected 1".format(target_under_test.label.name),
    )
    asserts.equals(env, target_under_test.label, entries[0].owner)
    module_symvers_restore_path = entries[0].restore_path
    asserts.true(
        env,
        target_under_test.label.name in module_symvers_restore_path,
        "Module.symvers is restored to {}, but it must contain {} to distinguish with other modules in the same package".format(
            module_symvers_restore_path,
            target_under_test.label.name,
        ),
    )

    expected_inputs = sets.make(ctx.files.expected_inputs)

    action = None
    mnemonic = "KernelModule"
    if ctx.attr._config_is_local[BuildSettingInfo].value:
        mnemonic += "ProcessWrapperSandbox"

    for a in target_under_test.actions:
        if a.mnemonic == mnemonic:
            action = a
    asserts.true(env, action, "Can't find action with mnemonic KernelModule")

    inputs = sets.make(action.inputs.to_list())
    asserts.true(
        env,
        sets.is_subset(expected_inputs, inputs),
        "Missing inputs to action {}".format(
            sets.to_list(sets.difference(expected_inputs, inputs)),
        ),
    )

    if len(ctx.files.unexpected_inputs) > 0:
        unexpected_inputs = sets.make(ctx.files.unexpected_inputs)
        asserts.false(
            env,
            sets.is_subset(unexpected_inputs, inputs),
            "Unexpected inputs to action {}".format(
                sets.to_list(sets.intersection(unexpected_inputs, inputs)),
            ),
        )

    check_ddk_headers_info(ctx, env)

    return analysistest.end(env)

ddk_module_test = analysistest.make(
    impl = _ddk_module_test_impl,
    attrs = {
        "expected_inputs": attr.label_list(allow_files = True),
        "unexpected_inputs": attr.label_list(allow_files = True),
        "expected_includes": attr.string_list(),
        "expected_hdrs": attr.label_list(allow_files = [".h"]),
        "_config_is_local": attr.label(
            default = "//build/kernel/kleaf:config_local",
        ),
    },
)

def _ddk_module_test_make(
        name,
        expected_inputs = None,
        unexpected_inputs = None,
        expected_hdrs = None,
        expected_includes = None,
        **kwargs):
    ddk_module(
        name = name + "_module",
        out = name + ".ko",
        tags = ["manual"],
        **kwargs
    )

    ddk_module_test(
        name = name,
        target_under_test = name + "_module",
        expected_inputs = expected_inputs,
        unexpected_inputs = unexpected_inputs,
        expected_hdrs = expected_hdrs,
        expected_includes = expected_includes,
    )

def _conditional_srcs_test(
        name,
        kernel_build):
    ddk_module(
        name = name + "_module",
        kernel_build = kernel_build,
        out = name + "_module.ko",
        conditional_srcs = {
            "CONFIG_A": {
                True: ["cond_srcs/a_y.c"],
                False: ["cond_srcs/a_n.c"],
            },
        },
        tags = ["manual"],
    )

    get_top_level_file(
        name = name + "_kbuild",
        filename = "Kbuild",
        target = name + "_module_makefiles",
        tags = ["manual"],
    )

    write_file(
        name = name + "_expected",
        out = name + "_expected/Kbuild",
        content = [
            "{}_module-$(CONFIG_A) += cond_srcs/a_y.o".format(name),
            "ifeq ($(CONFIG_A),)",
            "{}_module-y += cond_srcs/a_n.o".format(name),
            "endif # ifeq ($(CONFIG_A),)",
        ],
    )

    contain_lines_test(
        name = name,
        expected = name + "_expected",
        actual = name + "_kbuild",
        order = True,
    )

def _shared_module_symvers_tests(name, kernel_build, base, legacy_module_a, legacy_module_b):
    """Tests owner-based deduplication in _check_module_symvers_restore_path."""
    tests = []

    # Same owner via direct dep and kernel_module_group should pass.
    kernel_module_group(
        name = name + "_group_base",
        srcs = [base],
        tags = ["manual"],
    )
    _ddk_module_test_make(
        name = name + "_direct_and_group",
        srcs = ["dep.c"],
        kernel_build = kernel_build,
        deps = [
            base,
            name + "_group_base",
        ],
    )
    tests.append(name + "_direct_and_group")

    # Same owner referenced by two ddk_submodules (direct and via group) should pass.
    ddk_submodule(
        name = name + "_sub_a",
        out = name + "_sub_a.ko",
        srcs = ["dep.c"],
        deps = [base],
        tags = ["manual"],
    )
    ddk_submodule(
        name = name + "_sub_b",
        out = name + "_sub_b.ko",
        srcs = ["self.c"],
        deps = [name + "_group_base"],
        tags = ["manual"],
    )
    ddk_module(
        name = name + "_two_submodules_module",
        kernel_build = kernel_build,
        deps = [
            name + "_sub_a",
            name + "_sub_b",
        ],
        tags = ["manual"],
    )
    ddk_module_test(
        name = name + "_two_submodules",
        target_under_test = name + "_two_submodules_module",
    )
    tests.append(name + "_two_submodules")

    # Distinct conflicting legacy kernel_modules wrapped in kernel_module_group still fail.
    kernel_module_group(
        name = name + "_group_legacy_a",
        srcs = [legacy_module_a],
        tags = ["manual"],
    )
    kernel_module_group(
        name = name + "_group_legacy_b",
        srcs = [legacy_module_b],
        tags = ["manual"],
    )
    ddk_module(
        name = name + "_legacy_conflict_groups_module",
        out = name + "_legacy_conflict_groups_module.ko",
        srcs = ["dep.c"],
        kernel_build = kernel_build,
        deps = [
            name + "_group_legacy_a",
            name + "_group_legacy_b",
        ],
        tags = ["manual"],
    )
    failure_test(
        name = name + "_legacy_conflict_groups",
        target_under_test = name + "_legacy_conflict_groups_module",
        error_message_substrs = [
            "Conflicting dependencies",
            legacy_module_a,
            legacy_module_b,
        ],
    )
    tests.append(name + "_legacy_conflict_groups")

    native.test_suite(
        name = name,
        tests = tests,
    )

def _ddk_library_symvers_action_test_impl(ctx):
    env = analysistest.begin(ctx)
    target_under_test = analysistest.target_under_test(env)

    mnemonic = "KernelModule"
    if ctx.attr._config_is_local[BuildSettingInfo].value:
        mnemonic += "ProcessWrapperSandbox"

    action = None
    for a in target_under_test.actions:
        if a.mnemonic == mnemonic:
            action = a
    asserts.true(env, action, "Can't find action with mnemonic {}".format(mnemonic))

    symvers_files = ctx.attr.symvers_owner[ModuleSymversFileInfo].module_symvers.to_list()
    asserts.equals(env, 1, len(symvers_files), "Expected 1 Module.symvers from symvers_owner")
    symvers_file = symvers_files[0]

    inputs = sets.make(action.inputs.to_list())
    cmd = action.argv[-1]
    if ctx.attr.expect_dep_setup:
        asserts.true(
            env,
            sets.contains(inputs, symvers_file),
            "Expected {} in action inputs".format(symvers_file.path),
        )
        asserts.true(
            env,
            "dep_setup.sh" in target_under_test[OutputGroupInfo],
            "Expected dep_setup.sh output group",
        )
        dep_setup_files = target_under_test[OutputGroupInfo]["dep_setup.sh"].to_list()
        asserts.equals(env, 1, len(dep_setup_files), "Expected 1 dep_setup.sh file")
        asserts.true(
            env,
            sets.contains(inputs, dep_setup_files[0]),
            "Expected {} in action inputs".format(dep_setup_files[0].path),
        )
        asserts.true(
            env,
            ". " + dep_setup_files[0].path in cmd,
            "Expected command to source {}".format(dep_setup_files[0].path),
        )
    else:
        asserts.false(
            env,
            sets.contains(inputs, symvers_file),
            "Unexpected {} in action inputs".format(symvers_file.path),
        )
        asserts.false(
            env,
            "dep_setup.sh" in target_under_test[OutputGroupInfo],
            "Unexpected dep_setup.sh output group on ddk_library",
        )

    if ctx.attr.expected_propagated_symvers:
        asserts.set_equals(
            env,
            sets.make(ctx.attr.symvers_owner[ModuleSymversInfo].entries.to_list()),
            sets.make(target_under_test[ModuleSymversInfo].entries.to_list()),
            "Expected ddk_library to propagate ModuleSymversInfo.entries",
        )

    return analysistest.end(env)

_ddk_library_symvers_action_test = analysistest.make(
    impl = _ddk_library_symvers_action_test_impl,
    attrs = {
        "symvers_owner": attr.label(
            mandatory = True,
            providers = [ModuleSymversFileInfo, ModuleSymversInfo],
        ),
        "expect_dep_setup": attr.bool(mandatory = True),
        "expected_propagated_symvers": attr.bool(),
        "_config_is_local": attr.label(
            default = "//build/kernel/kleaf:config_local",
        ),
    },
)

def _ddk_library_symvers_tests(name, kernel_build, legacy_module_a, legacy_module_b):
    """Tests Module.symvers propagation through ddk_library."""
    tests = []

    ddk_module(
        name = name + "_parent",
        out = name + "_parent.ko",
        srcs = ["base.c"],
        kernel_build = kernel_build,
        tags = ["manual"],
    )

    ddk_library(
        name = name + "_lib_a",
        srcs = ["dep.c"],
        kernel_build = kernel_build,
        deps = [name + "_parent"],
        tags = ["manual"],
    )

    ddk_library(
        name = name + "_lib_b",
        srcs = ["self.c"],
        kernel_build = kernel_build,
        deps = [name + "_parent"],
        tags = ["manual"],
    )

    # Baseline direct dep to compare deduplicated dep_setup.sh byte-for-byte.
    ddk_module(
        name = name + "_direct_module",
        out = name + "_direct.ko",
        srcs = ["self.c"],
        kernel_build = kernel_build,
        deps = [name + "_parent"],
        tags = ["manual"],
    )
    output_group_files(
        name = name + "_direct_dep_setup_sh",
        src = name + "_direct_module",
        output_group = "dep_setup.sh",
        tags = ["manual"],
    )
    write_file(
        name = name + "_expected_dep_setup_sh",
        out = name + "_expected_dep_setup_sh/dep_setup.sh",
        content = [
            "mkdir -p $(dirname ${{COMMON_OUT_DIR}}/{}/{}_parent_Module.symvers)".format(
                native.package_name(),
                name,
            ),
        ],
    )
    contain_lines_test(
        name = name + "_direct_dep_setup_content_test",
        expected = name + "_expected_dep_setup_sh",
        actual = name + "_direct_dep_setup_sh",
    )
    tests.append(name + "_direct_dep_setup_content_test")

    # ddk_library propagates ModuleSymversInfo but does not restore symvers in its own action.
    _ddk_library_symvers_action_test(
        name = name + "_library_skips_own_restore",
        target_under_test = name + "_lib_a",
        symvers_owner = name + "_parent",
        expect_dep_setup = False,
        expected_propagated_symvers = True,
    )
    tests.append(name + "_library_skips_own_restore")

    # child -> lib_a -> parent
    ddk_module(
        name = name + "_child_module",
        out = name + "_child.ko",
        srcs = ["self.c"],
        kernel_build = kernel_build,
        deps = [name + "_lib_a"],
        tags = ["manual"],
    )

    # child -> [parent, lib_a] (duplicate direct + library dep)
    ddk_module(
        name = name + "_child_with_parent_module",
        out = name + "_child_with_parent.ko",
        srcs = ["self.c"],
        kernel_build = kernel_build,
        deps = [
            name + "_parent",
            name + "_lib_a",
        ],
        tags = ["manual"],
    )

    # child -> [lib_a, lib_b] -> parent (diamond)
    ddk_module(
        name = name + "_child_diamond_module",
        out = name + "_child_diamond.ko",
        srcs = ["base.c"],
        kernel_build = kernel_build,
        deps = [
            name + "_lib_a",
            name + "_lib_b",
        ],
        tags = ["manual"],
    )

    # child -> submodule -> lib_a -> parent
    ddk_submodule(
        name = name + "_sub",
        out = name + "_sub.ko",
        srcs = ["self.c"],
        deps = [name + "_lib_a"],
        tags = ["manual"],
    )
    ddk_module(
        name = name + "_child_via_submodule_module",
        kernel_build = kernel_build,
        deps = [name + "_sub"],
        tags = ["manual"],
    )

    for suffix in (
        "child",
        "child_with_parent",
        "child_diamond",
        "child_via_submodule",
    ):
        _ddk_library_symvers_action_test(
            name = "{}_{}".format(name, suffix),
            target_under_test = "{}_{}_module".format(name, suffix),
            symvers_owner = name + "_parent",
            expect_dep_setup = True,
        )
        tests.append("{}_{}".format(name, suffix))

        output_group_files(
            name = "{}_{}_dep_setup_sh".format(name, suffix),
            src = "{}_{}_module".format(name, suffix),
            output_group = "dep_setup.sh",
            tags = ["manual"],
        )
        diff_test(
            name = "{}_{}_dep_setup_diff_test".format(name, suffix),
            file1 = name + "_direct_dep_setup_sh",
            file2 = "{}_{}_dep_setup_sh".format(name, suffix),
        )
        tests.append("{}_{}_dep_setup_diff_test".format(name, suffix))

    # Distinct conflicting legacy kernel_modules in the same package still fail through ddk_library.
    ddk_library(
        name = name + "_lib_legacy_a",
        srcs = ["dep.c"],
        kernel_build = kernel_build,
        deps = [legacy_module_a],
        tags = ["manual"],
    )
    ddk_library(
        name = name + "_lib_legacy_b",
        srcs = ["self.c"],
        kernel_build = kernel_build,
        deps = [legacy_module_b],
        tags = ["manual"],
    )
    ddk_module(
        name = name + "_legacy_conflict_via_libs_module",
        out = name + "_legacy_conflict_via_libs_module.ko",
        srcs = ["base.c"],
        kernel_build = kernel_build,
        deps = [
            name + "_lib_legacy_a",
            name + "_lib_legacy_b",
        ],
        tags = ["manual"],
    )
    failure_test(
        name = name + "_legacy_conflict_via_libs",
        target_under_test = name + "_legacy_conflict_via_libs_module",
        error_message_substrs = [
            "Conflicting dependencies",
            legacy_module_a,
            legacy_module_b,
        ],
    )
    tests.append(name + "_legacy_conflict_via_libs")

    ddk_module(
        name = name + "_legacy_conflict_direct_and_lib_module",
        out = name + "_legacy_conflict_direct_and_lib_module.ko",
        srcs = ["base.c"],
        kernel_build = kernel_build,
        deps = [
            legacy_module_a,
            name + "_lib_legacy_b",
        ],
        tags = ["manual"],
    )
    failure_test(
        name = name + "_legacy_conflict_direct_and_lib",
        target_under_test = name + "_legacy_conflict_direct_and_lib_module",
        error_message_substrs = [
            "Conflicting dependencies",
            legacy_module_a,
            legacy_module_b,
        ],
    )
    tests.append(name + "_legacy_conflict_direct_and_lib")

    native.test_suite(
        name = name,
        tests = tests,
    )

def ddk_module_test_suite(name):
    """Tests for `ddk_module`.

    Args:
        name: name of the test suite."""

    kernel_build(
        name = name + "_kernel_build",
        outs = ["vmlinux"],
        tags = ["manual"],
        make_goals = [],
        pahole = "//build/kernel/kleaf/tests:fake_pahole",
    )

    kernel_module(
        name = name + "_legacy_module_a",
        kernel_build = name + "_kernel_build",
        tags = ["manual"],
    )

    kernel_module(
        name = name + "_legacy_module_b",
        kernel_build = name + "_kernel_build",
        tags = ["manual"],
    )

    ddk_module(
        name = name + "_self",
        out = name + "_self.ko",
        srcs = ["self.c"],
        kernel_build = name + "_kernel_build",
        tags = ["manual"],
    )

    ddk_module(
        name = name + "_base",
        out = name + "_base.ko",
        srcs = ["base.c"],
        kernel_build = name + "_kernel_build",
        tags = ["manual"],
    )

    ddk_headers(
        name = name + "_headers",
        includes = ["include"],
        hdrs = ["include/subdir.h"],
        tags = ["manual"],
    )

    tests = []

    _ddk_module_test_make(
        name = name + "_simple",
        srcs = ["self.c"],
        kernel_build = name + "_kernel_build",
    )
    tests.append(name + "_simple")

    _ddk_module_test_make(
        name = name + "_dep",
        srcs = ["dep.c"],
        kernel_build = name + "_kernel_build",
        deps = [name + "_base"],
    )
    tests.append(name + "_dep")

    _ddk_module_test_make(
        name = name + "_dep2",
        srcs = ["dep.c"],
        kernel_build = name + "_kernel_build",
        deps = [name + "_base", name + "_self"],
    )
    tests.append(name + "_dep2")

    _ddk_module_test_make(
        name = name + "_local_headers",
        srcs = ["dep.c", "include/subdir.h"],
        kernel_build = name + "_kernel_build",
        expected_inputs = ["include/subdir.h"],
    )
    tests.append(name + "_local_headers")

    _ddk_module_test_make(
        name = name + "_external_headers",
        srcs = ["dep.c"],
        kernel_build = name + "_kernel_build",
        deps = [name + "_headers"],
        expected_inputs = ["include/subdir.h"],
    )
    tests.append(name + "_external_headers")

    _ddk_module_test_make(
        name = name + "_depend_on_legacy_module",
        srcs = ["dep.c"],
        kernel_build = name + "_kernel_build",
        deps = [name + "_legacy_module_a"],
    )
    tests.append(name + "_depend_on_legacy_module")

    _ddk_module_test_make(
        name = name + "_generate_btf",
        srcs = ["self.c"],
        kernel_build = name + "_kernel_build",
        generate_btf = True,
        expected_inputs = [name + "_kernel_build/vmlinux"],
    )
    tests.append(name + "_generate_btf")

    _ddk_module_test_make(
        name = name + "_no_generate_btf",
        srcs = ["self.c"],
        kernel_build = name + "_kernel_build",
        generate_btf = False,
        unexpected_inputs = [name + "_kernel_build/vmlinux"],
    )
    tests.append(name + "_no_generate_btf")

    ddk_module(
        name = name + "_depend_on_legacy_modules_in_the_same_package_module",
        out = name + "_depend_on_legacy_modules_in_the_same_package_module.ko",
        srcs = ["dep.c"],
        kernel_build = name + "_kernel_build",
        deps = [name + "_legacy_module_a", name + "_legacy_module_b"],
        tags = ["manual"],
    )
    failure_test(
        name = name + "_depend_on_legacy_modules_in_the_same_package",
        target_under_test = name + "_depend_on_legacy_modules_in_the_same_package_module",
        error_message_substrs = [
            "Conflicting dependencies",
            name + "_legacy_module_a",
            name + "_legacy_module_b",
        ],
    )
    tests.append(name + "_depend_on_legacy_modules_in_the_same_package")

    _ddk_module_test_make(
        name = name + "_exported_headers",
        srcs = ["dep.c"],
        kernel_build = name + "_kernel_build",
        hdrs = ["include/subdir.h"],
        includes = ["include"],
        expected_inputs = ["include/subdir.h"],
        expected_hdrs = ["include/subdir.h"],
        expected_includes = [native.package_name() + "/include"],
    )
    tests.append(name + "_exported_headers")

    ddk_module(
        name = name + "_no_out_module",
        tags = ["manual"],
        kernel_build = name + "_kernel_build",
    )
    failure_test(
        name = name + "_no_out",
        target_under_test = name + "_no_out_module",
        error_message_substrs = ["out is not specified."],
    )
    tests.append(name + "_no_out")

    _conditional_srcs_test(
        name = name + "_conditional_srcs_test",
        kernel_build = name + "_kernel_build",
    )
    tests.append(name + "_conditional_srcs_test")

    _shared_module_symvers_tests(
        name = name + "_shared_module_symvers",
        kernel_build = name + "_kernel_build",
        base = name + "_base",
        legacy_module_a = name + "_legacy_module_a",
        legacy_module_b = name + "_legacy_module_b",
    )
    tests.append(name + "_shared_module_symvers")

    _ddk_library_symvers_tests(
        name = name + "_ddk_library_symvers",
        kernel_build = name + "_kernel_build",
        legacy_module_a = name + "_legacy_module_a",
        legacy_module_b = name + "_legacy_module_b",
    )
    tests.append(name + "_ddk_library_symvers")

    native.test_suite(
        name = name,
        tests = tests,
    )
