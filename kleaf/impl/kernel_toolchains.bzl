# Copyright (C) 2023 The Android Open Source Project
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

"""Helper for `kernel_env` to get toolchains for different platforms."""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_skylib//lib:sets.bzl", "sets")
load("@bazel_skylib//lib:shell.bzl", "shell")
load(
    ":common_providers.bzl",
    "KernelEnvToolchainsInfo",
    "KernelPlatformToolchainInfo",
)

visibility("//build/kernel/kleaf/...")

_RustEnvInfo = provider(
    "return value of rust env subrule",
    fields = {
        "cmd": "command line",
        "inputs": "depset of files",
    },
)

def _quote_prepend_cwd(value):
    """Prepends $PWD to value.

    Returns:
        quoted shell value
    """
    if not value.startswith("/"):
        return "${PWD}/" + shell.quote(value)
    return shell.quote(value)

def _get_target_arch(ctx):
    if ctx.target_platform_has_constraint(ctx.attr._platform_cpu_arm[platform_common.ConstraintValueInfo]):
        return "arm"
    if ctx.target_platform_has_constraint(ctx.attr._platform_cpu_arm64[platform_common.ConstraintValueInfo]):
        return "arm64"
    if ctx.target_platform_has_constraint(ctx.attr._platform_cpu_i386[platform_common.ConstraintValueInfo]):
        return "i386"
    if ctx.target_platform_has_constraint(ctx.attr._platform_cpu_riscv64[platform_common.ConstraintValueInfo]):
        return "riscv64"
    if ctx.target_platform_has_constraint(ctx.attr._platform_cpu_x86_64[platform_common.ConstraintValueInfo]):
        return "x86_64"
    fail("{}: Cannot determine target platform.".format(ctx.label))

def _quote_sanitize_flags(flags):
    """Turns paths into ones relative to $PWD for each flag.

    Kbuild executes the compiler in subdirectories, hence an absolute path is needed.

    Returns:
        quoted shell value
    """

    result_quoted_flags = []

    long_flags = [
        "--sysroot",
        "-iquote",
        "-isystem",
    ]

    short_flags = [
        "-I",
        "-L",
    ]

    prev = None
    for _index, flag in enumerate(flags):
        if prev in long_flags or prev in short_flags:
            result_quoted_flags.append(_quote_prepend_cwd(flag))
        elif any([flag.startswith(long_flag + "=") for long_flag in long_flags]):
            key, value = flag.split("=", 2)
            result_quoted_flags.append("{}={}".format(key, _quote_prepend_cwd(value)))
        elif any([flag.startswith(short_flag) for short_flag in short_flags]):
            key, value = flag[:2], flag[2:]
            result_quoted_flags.append("{}{}".format(key, _quote_prepend_cwd(value)))
        else:
            result_quoted_flags.append(shell.quote(flag))

        prev = flag

    return "' '".join(result_quoted_flags)

def _kernel_toolchains_impl(ctx):
    exec = ctx.attr.exec_toolchain[KernelPlatformToolchainInfo]
    target = ctx.attr.target_toolchain[KernelPlatformToolchainInfo]

    # Ensures that the resolved toolchain for the two platforms equal.
    if target.compiler_version != exec.compiler_version:
        fail("{}: Target platform has compiler version {} but exec platform has {}".format(
            ctx.label,
            target.compiler_version,
            exec.compiler_version,
        ))
    actual_toolchain_version = target.compiler_version

    all_files_transitive = [exec.all_files, target.all_files]
    target_arch = _get_target_arch(ctx)

    quoted_bin_paths = sets.to_list(sets.make([
        _quote_prepend_cwd(exec.bin_path),
        _quote_prepend_cwd(target.bin_path),
        _quote_prepend_cwd(exec.bin_path_short),
        _quote_prepend_cwd(target.bin_path_short),
    ]))

    setup_env_var_cmd = """
        export PATH={quoted_bin_paths}:${{PATH}}
    """.format(
        quoted_bin_paths = ":".join(quoted_bin_paths),
    )

    kernel_setup_env_var_cmd = setup_env_var_cmd

    # RUNPATH_EXECROOT: A heuristic path to execroot expressed relative to $ORIGIN.
    # RUNPATH_EXECROOT assumes that all binaries built by Kbuild are 1~3 levels
    #   below OUT_DIR,
    #   e.g. $OUT_DIR/scripts/sign-file, $OUT_DIR/tools/bpf/resolve_btfids/resolve_btfids
    # If this ever changes, edit kleaf_internal_eval_ldflags and add more levels.
    #
    # We use `realpath -s` (no-symlinks) to calculate relative paths.
    #
    # When building locally (with --config=local), OUT_DIR is overridden to a host cache directory:
    #   OUT_DIR = /path/to/workspace/out/cache/HASH/common
    # And ROOT_DIR (execroot) is:
    #   ROOT_DIR = /path/to/workspace/out/bazel/output_user_root/HASH/execroot/_main
    #
    # We also want to calculate the rpath for the expected default OUT_DIR (for downstream sandboxed actions):
    #   DEFAULT_OUT_DIR = ROOT_DIR/out/android-mainline/common
    #
    # In the local execution environment, ROOT_DIR contains a symlink `out` pointing to the host `out` directory:
    #   ROOT_DIR/out -> /path/to/workspace/out
    #
    # If we use standard `realpath` (following symlinks):
    #   realpath ROOT_DIR --relative-to DEFAULT_OUT_DIR
    # Resolves DEFAULT_OUT_DIR to:
    #   /path/to/workspace/out/android-mainline/common
    # Resulting in a "dirty" host-escaping relative path:
    #   ../../bazel/output_user_root/HASH/execroot/_main
    #
    # If we use `realpath -s` (ignoring symlinks):
    #   realpath -s ROOT_DIR --relative-to DEFAULT_OUT_DIR
    # Treats `out` as a regular directory, yielding a "clean" relative path:
    #   ../../..
    # This clean path is necessary for downstream actions running in a sandbox where `out` is a real directory.
    kernel_setup_env_var_cmd += """
        export HOSTCFLAGS={quoted_hostcflags}
        export USERCFLAGS={quoted_usercflags}
        export HOSTLDFLAGS={quoted_hostldflags}
        export USERLDFLAGS={quoted_userldflags}

        mkdir -p ${{OUT_DIR}}
        # Append to *LDFLAGS based on the current settings of $OUT_DIR.
        function kleaf_internal_append_one_ldflags() {{
            local backtrack_relative=$1
            local RUNPATH_EXECROOT='$$$$\\{{ORIGIN\\}}/'"${{backtrack_relative}}"
            export HOSTLDFLAGS="${{HOSTLDFLAGS}} "{hostldexpr}
            export USERLDFLAGS="${{USERLDFLAGS}} "{userldexpr}
        }}
        export -f kleaf_internal_append_one_ldflags

        function kleaf_internal_eval_ldflags() {{
            local relative_to_output="$(realpath -s ${{ROOT_DIR}} --relative-to ${{OUT_DIR}})"
            local relative_to_output_prefix="${{relative_to_output%%[!./]*}}"
            local relative_to_output_suffix="${{relative_to_output#${{relative_to_output_prefix}}}}"
            local relative_depth="${{relative_to_output_prefix//[^\\/]/}}"
            # This comes from the maximum path seen so far (e.g.):
            #   arch/arm64/kernel/pi/relacheck and arch/arm64/kvm/hyp/nvhe/gen-hyprel
            local max_depth=$((${{#relative_depth}} + 7))
            local backtrack=""
            for depth in $(seq 1 ${{max_depth}}); do
                backtrack="${{backtrack}}.."
                kleaf_internal_append_one_ldflags "${{backtrack}}/${{relative_to_output_suffix}}"
                backtrack="${{backtrack}}/"
            done
        }}
        export -f kleaf_internal_eval_ldflags

        kleaf_internal_eval_ldflags
    """.format(
        quoted_hostcflags = _quote_sanitize_flags(exec.cflags),
        quoted_usercflags = _quote_sanitize_flags(target.cflags),
        quoted_hostldflags = _quote_sanitize_flags(exec.ldflags),
        hostldexpr = exec.ldexpr,
        quoted_userldflags = _quote_sanitize_flags(target.ldflags),
        userldexpr = target.ldexpr,
    )
    rust_env = _get_rust_env(
        rust_toolchain = ctx.toolchains["@rules_rust//rust:toolchain_type"],
        bindgen_toolchain = ctx.toolchains["@rules_rust_bindgen//:toolchain_type"],
        host_libc = exec.libc,
        exec_info = exec,
        exec_glibc_info = ctx.attr.exec_glibc_toolchain[KernelPlatformToolchainInfo],
    )
    kernel_setup_env_var_cmd += rust_env.cmd
    all_files_transitive.append(rust_env.inputs)

    # Kleaf clang bins are under kleaf/parent, so CLANG_PREBUILT_BIN in
    # build.config.common is incorrect. Manually set additional PATH's.

    return KernelEnvToolchainsInfo(
        all_files = depset(transitive = all_files_transitive),
        target_arch = target_arch,
        setup_env_var_cmd = setup_env_var_cmd,
        kernel_setup_env_var_cmd = kernel_setup_env_var_cmd,
        compiler_version = actual_toolchain_version,
        host_runpaths = exec.runpaths,
        host_sysroot = exec.sysroot,
    )

def _get_rust_env_impl(_subrule_ctx, rust_toolchain, bindgen_toolchain, host_libc, exec_info, exec_glibc_info):
    if not rust_toolchain or not bindgen_toolchain:
        return _RustEnvInfo(
            inputs = depset(),
            # Always declare this function so we can use it unconditionally when handling --cache_dir
            cmd = """
                function kleaf_internal_eval_rust_flags() { :; }
                export -f kleaf_internal_eval_rust_flags
            """,
        )

    rustc = rust_toolchain.rustc
    bindgen_file = bindgen_toolchain.bindgen

    bindgen_transitive = []
    bindgen_direct = []
    if bindgen_file:
        bindgen_direct.append(bindgen_file)
    if bindgen_toolchain.libclang:
        bindgen_transitive.append(bindgen_toolchain.libclang[DefaultInfo].files)
    if bindgen_toolchain.libstdcxx:
        bindgen_transitive.append(bindgen_toolchain.libstdcxx[DefaultInfo].files)

    # Skip the clang executable.
    # Our Rust toolchains does not specify the clang executable. Plus, just the executable
    # alone wouldn't be sufficient -- we would need its runfiles. Since cc_toolchain.all_files are
    # added anyways, we just do an assertion here.

    bindgen_files = depset(direct = bindgen_direct, transitive = bindgen_transitive)

    if host_libc == "musl":
        target = "x86_64-unknown-linux-musl"
    elif host_libc == "glibc":
        target = "x86_64-unknown-linux-gnu"
    else:
        fail("Unknown libc {}".format(host_libc))

    if rust_toolchain.exec_triple.abi == "gnu":
        proc_macro_info = exec_glibc_info
    elif rust_toolchain.exec_triple.abi == "musl":
        proc_macro_info = exec_info
    else:
        fail("{}: Unknown ABI for rust toolchain: {}".format(_subrule_ctx.label, rust_toolchain.exec_triple))

    # RUNPATH_EXECROOT: A heuristic path to execroot expressed relative to $ORIGIN.
    # RUNPATH_EXECROOT assumes that all binaries built by Kbuild are several levels
    #   below OUT_DIR,
    #   e.g. $OUT_DIR/scripts/generate_rust_targets
    # If this ever changes, edit kleaf_internal_eval_rust_flags and add more levels.
    cmd = """
        export PATH="${{PATH}}:${{ROOT_DIR}}/"{quoted_rust_bin}":${{ROOT_DIR}}/"{quoted_rust_bin_short}":${{ROOT_DIR}}/"{quoted_clangtools_bin}":${{ROOT_DIR}}/"{quoted_clangtools_bin_short}
        export HOSTRUSTFLAGS="--target {target}"
        export PROCMACROLDFLAGS={quoted_proc_macro_ldflags}

        function kleaf_internal_append_one_rust_flags() {{
            local backtrack_relative=$1
            local RUNPATH_EXECROOT='$$$$\\{{ORIGIN\\}}/'"${{backtrack_relative}}$(realpath -s ${{ROOT_DIR}} --relative-to ${{OUT_DIR}})"
            local RUNPATH_EXECROOT_LESSQUOTE='$$$$ORIGIN/'"${{backtrack_relative}}$(realpath -s ${{ROOT_DIR}} --relative-to ${{OUT_DIR}})"
            export HOSTRUSTFLAGS="${{HOSTRUSTFLAGS}} "-Clink-args=-Wl,-rpath,${{RUNPATH_EXECROOT}}/{quoted_rust_bin}/../lib64
            export PROCMACROLDFLAGS="${{PROCMACROLDFLAGS}} "-Wl,-rpath,${{RUNPATH_EXECROOT_LESSQUOTE}}/{quoted_rust_bin}/../lib64
        }}
        export -f kleaf_internal_append_one_rust_flags
        function kleaf_internal_eval_rust_flags() {{
            kleaf_internal_append_one_rust_flags ../
        }}
        export -f kleaf_internal_eval_rust_flags

        kleaf_internal_eval_rust_flags
    """.format(
        target = target,
        quoted_rust_bin = shell.quote(rustc.dirname),
        quoted_rust_bin_short = shell.quote(paths.dirname(rustc.short_path)),
        quoted_clangtools_bin = shell.quote(bindgen_file.dirname),
        quoted_clangtools_bin_short = shell.quote(paths.dirname(bindgen_file.short_path)),
        quoted_proc_macro_ldflags = _quote_sanitize_flags(proc_macro_info.ldflags),
    )

    return _RustEnvInfo(
        inputs = depset(transitive = [rust_toolchain.all_files, proc_macro_info.all_files, bindgen_files]),
        cmd = cmd,
    )

_get_rust_env = subrule(
    implementation = _get_rust_env_impl,
)

kernel_toolchains = rule(
    doc = """Helper for `kernel_env` to get toolchains for different platforms.""",
    implementation = _kernel_toolchains_impl,
    attrs = {
        "exec_toolchain": attr.label(
            cfg = "exec",
            providers = [KernelPlatformToolchainInfo],
        ),
        "exec_glibc_toolchain": attr.label(
            cfg = "exec",
            providers = [KernelPlatformToolchainInfo],
        ),
        "target_toolchain": attr.label(
            providers = [KernelPlatformToolchainInfo],
        ),
        # This is not used, but the dependency ensures that if
        # --noincompatible_kernel_use_resolved_toolchains is specified, an error message is printed.
        "_kernel_use_resolved_toolchains": attr.label(
            default = "//build/kernel/kleaf:incompatible_kernel_use_resolved_toolchains",
        ),
        "_platform_cpu_arm": attr.label(default = "@platforms//cpu:arm"),
        "_platform_cpu_arm64": attr.label(default = "@platforms//cpu:arm64"),
        "_platform_cpu_i386": attr.label(default = "@platforms//cpu:i386"),
        "_platform_cpu_riscv64": attr.label(default = "@platforms//cpu:riscv64"),
        "_platform_cpu_x86_64": attr.label(default = "@platforms//cpu:x86_64"),
    },
    toolchains = [
        config_common.toolchain_type("@rules_rust//rust:toolchain_type", mandatory = False),
        config_common.toolchain_type("@rules_rust_bindgen//:toolchain_type", mandatory = False),
    ],
    subrules = [_get_rust_env],
)
