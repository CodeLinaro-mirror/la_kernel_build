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

"""Wraps prebuilt DDK module files, so it can be used as a dependency."""

load(
    ":common_providers.bzl",
    "DdkConfigInfo",
    "ModuleSymversFileInfo",
)
load(":ddk/copy_ddk_prebuilt_step.bzl", "copy_ddk_prebuilt_step")
load(":ddk/ddk_headers.bzl", "ddk_headers_common_impl")
load(":hermetic_toolchain.bzl", "hermetic_toolchain")

visibility("//build/kernel/kleaf/...")

def _ddk_prebuilt_module_impl(ctx):
    hermetic_tools = hermetic_toolchain.get(ctx)

    out_stem = ctx.file.src.basename.removesuffix("." + ctx.file.src.extension)
    all_files = []
    infos = []

    # Required output
    module_ko = copy_ddk_prebuilt_step(
        hermetic_tools,
        ctx.file.src,
        "{}/{}.ko".format(ctx.label.name, out_stem),
        "Ko",
    )
    all_files.append(module_ko)

    # ModuleSymversFileInfo
    if ctx.file.module_symvers:
        module_symvers = copy_ddk_prebuilt_step(
            hermetic_tools,
            ctx.file.module_symvers,
            "{}/Module.symvers".format(ctx.label.name),
            "ModuleSymvers",
        )
        all_files.append(module_symvers)
        infos.append(ModuleSymversFileInfo(module_symvers = depset([module_symvers])))
    else:
        infos.append(ModuleSymversFileInfo(module_symvers = depset()))

    # DdkConfigInfo
    if ctx.attr.config:
        infos.append(ctx.attr.config[DdkConfigInfo])

    # DdkHeadersInfo
    if ctx.attr.hdrs or ctx.attr.includes or ctx.attr.linux_includes:
        ddk_headers_info = ddk_headers_common_impl(
            ctx.label,
            ctx.attr.hdrs,
            ctx.attr.includes,
            ctx.attr.linux_includes,
        )
        infos.append(ddk_headers_info)

    infos.append(DefaultInfo(files = depset(all_files)))
    return infos

ddk_prebuilt_module = rule(
    implementation = _ddk_prebuilt_module_impl,
    doc = """Wraps ddk_module prebuilt files so it can be used in [ddk_module.srcs](#ddk_module-srcs).

        Example:

        ```
        # Optional
        ddk_config(
            name = "foo_config",
        )
        ddk_prebuilt_module(
            name = "foo",
            src = "foo.ko",
            module_symvers = "foo_Module.symvers",
            config = ":foo_config", # Optional
        )
        ```
    """,
    attrs = {
        "src": attr.label(
            mandatory = True,
            allow_single_file = True,
            doc = "The .ko file.",
        ),
        "module_symvers": attr.label(
            allow_single_file = True,
            doc = "Module.symvers file.",
        ),
        "config": attr.label(
            doc = "A [ddk_config](#ddk_config).",
            providers = [DdkConfigInfo],
        ),
        "hdrs": attr.label_list(
            allow_files = True,
            doc = "[ddk_headers.hdrs](#ddk_headers-hdrs)",
        ),
        "includes": attr.string_list(
            doc = "[ddk_headers.hdrs](#ddk_headers-includes)",
        ),
        "linux_includes": attr.string_list(
            doc = "[ddk_headers.hdrs](#ddk_headers-linux_includes)",
        ),
    },
    subrules = [
        copy_ddk_prebuilt_step,
    ],
    toolchains = [hermetic_toolchain.type],
)
