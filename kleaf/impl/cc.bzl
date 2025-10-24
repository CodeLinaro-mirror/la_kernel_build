# Copyright (C) 2025 The Android Open Source Project
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

"""Utilities to get files from CC toolchain."""

load("@rules_cc//cc:find_cc_toolchain.bzl", "find_cc_toolchain", "use_cc_toolchain")
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("//prebuilts/clang/host/linux-x86/kleaf:action_names.bzl", "READELF_ACTION_NAME")
load(":common_providers.bzl", "CcToolInfo")

visibility("//build/kernel/kleaf/...")

def _readelf_tool_impl(ctx):
    cc_toolchain = find_cc_toolchain(ctx, mandatory = True)
    feature_configuration = cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = cc_toolchain,
        requested_features = ctx.features,
    )
    readelf_executable = cc_common.get_tool_for_action(
        feature_configuration = feature_configuration,
        action_name = READELF_ACTION_NAME,
    )

    return [
        CcToolInfo(
            readelf_path = readelf_executable,
            all_files = cc_toolchain.all_files,
        ),
    ]

readelf_tool = rule(
    doc = "Resolves to the readelf executable from the resolved CC toolchain.",
    implementation = _readelf_tool_impl,
    toolchains = use_cc_toolchain(mandatory = True),
    fragments = ["cpp"],
)
