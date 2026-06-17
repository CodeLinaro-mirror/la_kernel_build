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

"""Exposes kernel config includes to build devicetrees."""

load("@rules_devicetree//devicetree:devicetree_library.bzl", "devicetree_library")
load("//build/kernel/kleaf/impl:hermetic_toolchain.bzl", "hermetic_toolchain")
load(":common_providers.bzl", "KernelBuildConfigDirectoryInfo")

visibility("//build/kernel/kleaf/...")

def _kernel_config_include_dir_impl(ctx):
    if KernelBuildConfigDirectoryInfo not in ctx.attr.kernel_build:
        fail("{}: kernel_build target {} does not provide KernelBuildConfigDirectoryInfo".format(
            ctx.label,
            ctx.attr.kernel_build.label,
        ))

    config_out_dir = ctx.attr.kernel_build[KernelBuildConfigDirectoryInfo].config_out_dir
    if not config_out_dir:
        fail("{}: kernel_build target {} does not expose config_out_dir (it might be a kernel_filegroup without config_out_dir specified)".format(
            ctx.label,
            ctx.attr.kernel_build.label,
        ))

    hermetic_tools = hermetic_toolchain.get(ctx)
    include_dir = ctx.actions.declare_directory(ctx.attr.name)

    ctx.actions.run_shell(
        inputs = [config_out_dir],
        outputs = [include_dir],
        tools = hermetic_tools.deps,
        command = hermetic_tools.setup + """
            rsync -aL {config_out_dir}/include/ {include_dir}/
        """.format(
            config_out_dir = config_out_dir.path,
            include_dir = include_dir.path,
        ),
        progress_message = "Extracting Kconfig headers for DT %{label}",
        mnemonic = "KernelConfigIncludeDir",
    )

    return [
        DefaultInfo(
            files = depset([include_dir]),
        ),
    ]

_kernel_config_include_dir = rule(
    implementation = _kernel_config_include_dir_impl,
    attrs = {
        "kernel_build": attr.label(
            mandatory = True,
            providers = [KernelBuildConfigDirectoryInfo],
            doc = "The [`kernel_build`](#kernel_build) or [`kernel_filegroup`](#kernel_filegroup) target",
        ),
    },
    toolchains = [hermetic_toolchain.type],
)

def _kernel_config_devicetree_library_impl(name, kernel_build, visibility, **kwargs):
    include_dir_name = name + "_kconfig_include_dir"

    _kernel_config_include_dir(
        name = include_dir_name,
        kernel_build = kernel_build,
        visibility = ["//visibility:private"],
        **kwargs
    )

    # devicetree_library's `includes` attribute takes a list of LABELS to
    # targets that produce directories (unlike standard cc_* rules where
    # `includes` is a list of string paths).
    # Here, include_dir_name is a helper target that produces a TreeArtifact
    # containing the include/ directory.
    devicetree_library(
        name = name,
        hdrs = [":" + include_dir_name],
        includes = [":" + include_dir_name],
        visibility = visibility,
        **kwargs
    )

kernel_config_devicetree_library = macro(
    implementation = _kernel_config_devicetree_library_impl,
    inherit_attrs = _kernel_config_include_dir,
    doc = """Creates a
        [`devicetree_library`](https://github.com/bazel-contrib/rules_devicetree/blob/main/docs/api/devicetree_library.md)
        target that exposes kernel config includes.

        This is useful for devicetree builds that need to access kernel configuration
        headers (e.g. `linux/kconfig.h` for `IS_ENABLED` macro).
""",
)
