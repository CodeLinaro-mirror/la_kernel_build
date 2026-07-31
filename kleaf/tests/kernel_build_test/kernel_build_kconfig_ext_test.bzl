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

"""
Test kconfig_ext validation in kernel_build / kernel_env.
"""

load("//build/kernel/kleaf/impl:kernel_build.bzl", "kernel_build")
load("//build/kernel/kleaf/tests:failure_test.bzl", "failure_test")

def kernel_build_kconfig_ext_test(name):
    """Define tests for kconfig_ext validation.

    Args:
        name: Name of this test suite.
    """
    test_target = name + "_invalid_kconfig_ext_test"

    kernel_build(
        name = name + "_invalid_kconfig_ext_build",
        outs = [],
        make_goals = [],
        pahole = "//build/kernel/kleaf/tests:fake_pahole",
        kconfig_ext = "//build/kernel/kleaf/tests/kernel_build_test:BUILD.bazel",
        tags = ["manual"],
    )

    failure_test(
        name = test_target,
        target_under_test = ":" + name + "_invalid_kconfig_ext_build",
        error_message_substrs = [
            "kconfig_ext must be named 'Kconfig.ext'",
        ],
    )

    native.test_suite(
        name = name,
        tests = [test_target],
    )
