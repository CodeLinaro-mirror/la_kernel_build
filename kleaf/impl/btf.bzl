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

"""Builds vmlinux.btf."""

load("@rules_cc//cc:action_names.bzl", "ACTION_NAMES")
load("@rules_cc//cc:defs.bzl", "cc_common")
load("@rules_cc//cc:find_cc_toolchain.bzl", "find_cpp_toolchain", "use_cc_toolchain")
load("//build/kernel/kleaf:hermetic_tools.bzl", "hermetic_toolchain")
load(":debug.bzl", "debug")

visibility("//build/kernel/kleaf/...")

def _btf_impl(ctx):
    out_file = ctx.actions.declare_file("{}/vmlinux.btf".format(ctx.label.name))

    # Set up environment from hermetic tools.
    hermetic_tools = hermetic_toolchain.get(ctx)
    command = hermetic_tools.setup

    # Retrieve llvm-strip from clang toolchain.
    cc_toolchain = find_cpp_toolchain(ctx)
    feature_configuration = cc_common.configure_features(
        ctx = ctx,
        cc_toolchain = cc_toolchain,
        requested_features = ctx.features,
    )
    strip = cc_common.get_tool_for_action(
        feature_configuration = feature_configuration,
        action_name = ACTION_NAMES.strip,
    )

    # Create output directory and run pahole.
    command += """
              mkdir -p {out_dir}
              cp -Lp {vmlinux} {btf}
              {pahole} -J {btf}
              {strip} --strip-debug {btf}
    """.format(
        vmlinux = ctx.file.vmlinux.path,
        pahole = ctx.executable.pahole.path,
        btf = out_file.path,
        out_dir = out_file.dirname,
        strip = strip,
    )

    debug.print_scripts(ctx, command)
    ctx.actions.run_shell(
        mnemonic = "Btf",
        inputs = [ctx.file.vmlinux],
        outputs = [out_file],
        tools = [cc_toolchain.all_files, hermetic_tools.deps, ctx.executable.pahole],
        progress_message = "Building vmlinux.btf %{label}",
        command = command,
    )
    return DefaultInfo(files = depset([out_file]))

btf = rule(
    implementation = _btf_impl,
    doc = "Build vmlinux.btf",
    attrs = {
        "vmlinux": attr.label(
            mandatory = True,
            allow_single_file = True,
        ),
        "_cc_toolchain": attr.label(default = "//build/kernel/kleaf/impl:kernel_toolchains"),
        "pahole": attr.label(
            executable = True,
            cfg = "exec",
            doc = "Label to pahole executable",
        ),
        "_debug_print_scripts": attr.label(default = "//build/kernel/kleaf:debug_print_scripts"),
    },
    toolchains = [hermetic_toolchain.type] + use_cc_toolchain(),
    fragments = ["cpp"],
)
