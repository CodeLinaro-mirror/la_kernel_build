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

"""Builds `kernel-headers.tar.gz` and provides `CcInfo` for generated headers."""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")
load(
    ":common_providers.bzl",
    "KernelBuildGenHeadersInfo",
    "KernelBuildInfo",
    "KernelEnvInfo",
)
load(":debug.bzl", "debug")
load(":utils.bzl", "kernel_utils")

visibility("//build/kernel/kleaf/...")

def _kernel_headers_impl(ctx):
    out_dir_kernel_headers_tar = ctx.attr.kernel_build[KernelBuildInfo].out_dir_kernel_headers_tar
    arch = ctx.attr.kernel_build[KernelBuildGenHeadersInfo].arch
    srcarch = kernel_utils.get_src_arch(arch)

    inputs = [
        out_dir_kernel_headers_tar,
    ]
    transitive_inputs = [target.files for target in ctx.attr.srcs]
    transitive_inputs.append(ctx.attr.env[KernelEnvInfo].inputs)
    tools = ctx.attr.env[KernelEnvInfo].tools

    out_file = ctx.actions.declare_file("{}/kernel-headers.tar.gz".format(ctx.label.name))
    out_dir = ctx.actions.declare_directory(ctx.label.name + "_unpacked")

    command = ctx.attr.env[KernelEnvInfo].setup + """
            # Unpack generated headers for CcInfo and archive
              mkdir -p "{out_dir}"
              tar xf "{out_dir_kernel_headers_tar}" -C "{out_dir}"
            # Create archive
              (
                real_out_file=$(realpath {out_file})
                real_out_dir=$(realpath {out_dir})
                cd ${{ROOT_DIR}}/${{KERNEL_DIR}}
                find arch include ${{real_out_dir}} -name "*.h" -not -type d -print0 \
                    | tar czf ${{real_out_file}}                                \
                        --mode=u=rw,go=r                                        \
                        --absolute-names                                        \
                        --dereference                                           \
                        --transform "s,.*${{real_out_dir}},,"                   \
                        --transform "s,^/,,"                                    \
                        --transform "s,^,kernel-headers/,"                      \
                        --null -T -
              )
    """.format(
        out_file = out_file.path,
        out_dir = out_dir.path,
        out_dir_kernel_headers_tar = out_dir_kernel_headers_tar.path,
    )

    debug.print_scripts(ctx, command)
    ctx.actions.run_shell(
        mnemonic = "KernelHeaders",
        inputs = depset(inputs, transitive = transitive_inputs),
        outputs = [out_file, out_dir],
        tools = tools,
        progress_message = "Building kernel headers %{label}",
        command = command,
    )

    gen_includes = [
        paths.join(out_dir.path, "include"),
        paths.join(out_dir.path, "include/generated"),
        paths.join(out_dir.path, "arch", srcarch, "include"),
        paths.join(out_dir.path, "arch", srcarch, "include/generated"),
    ]

    compilation_context = cc_common.create_compilation_context(
        headers = depset([out_dir]),
        includes = depset(gen_includes),
    )

    return [
        DefaultInfo(files = depset([out_file])),
        CcInfo(compilation_context = compilation_context),
    ]

kernel_headers = rule(
    implementation = _kernel_headers_impl,
    doc = "Build `kernel-headers.tar.gz` and provide `CcInfo` for generated headers",
    attrs = {
        "srcs": attr.label_list(allow_files = True),
        "kernel_build": attr.label(
            mandatory = True,
            providers = [KernelBuildInfo, KernelBuildGenHeadersInfo],
        ),
        "env": attr.label(
            mandatory = True,
            providers = [KernelEnvInfo],
        ),
        "_debug_print_scripts": attr.label(default = "//build/kernel/kleaf:debug_print_scripts"),
    },
)
