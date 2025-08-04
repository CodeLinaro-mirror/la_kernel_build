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

"""Build dtbo."""

load(":common_providers.bzl", "KernelBuildInfo", "KernelSerializedEnvInfo")
load(":debug.bzl", "debug")
load(":utils.bzl", "kernel_utils", "utils")

visibility("//build/kernel/kleaf/...")

def _get_deprecation_warning(ctx):
    # Omit the warning if opts have been provided.
    if ctx.attr.opts:
        return ""
    return """
          if [[ -n ${{MKDTIMG_FLAGS}} ]] ; then
            KLEAF_MKDTIMG_FLAGS=$(echo "${{MKDTIMG_FLAGS% }}" | sed '/^$/d' | sed 's/\\S*/  "&",/g')
            echo "WARNING: MKDTIMG_FLAGS from build.config is DEPRECATED. Add opts:" >&2
            echo "opts = [\n${{KLEAF_MKDTIMG_FLAGS}}" >&2
            echo "],\nto {dtbo_target} target." >&2
            unset KLEAF_MKDTIMG_FLAGS
          fi
    """.format(dtbo_target = str(ctx.label.name))

def _get_mkdtimg_opts_cmd(ctx):
    if ctx.attr.opts:
        return " ".join(ctx.attr.opts)

    # Fallback to previous behavior, until is fully deprecated.
    return "${MKDTIMG_FLAGS}"

def _dtbo_image_impl(ctx):
    out_name = ctx.attr.out or (ctx.label.name + "/dtbo.img")
    output = ctx.actions.declare_file(out_name)
    dtbo_staging_dir = output.dirname + "/staging"
    inputs = []
    transitive_inputs = [target.files for target in ctx.attr.srcs]
    transitive_inputs.append(ctx.attr.kernel_build[KernelSerializedEnvInfo].inputs)
    tools = ctx.attr.kernel_build[KernelSerializedEnvInfo].tools

    command = kernel_utils.setup_serialized_env_cmd(
        serialized_env_info = ctx.attr.kernel_build[KernelSerializedEnvInfo],
        restore_out_dir_cmd = utils.get_check_sandbox_cmd(),
    )

    command += _get_deprecation_warning(ctx)
    mkdtimg_opts_cmd = _get_mkdtimg_opts_cmd(ctx)

    if ctx.file.config_file:
        inputs.append(ctx.file.config_file)
        command += """
                  mkdir -p {dtbo_staging_dir}
                  cp {srcs} {dtbo_staging_dir}

                # make dtbo
                  mkdtimg cfg_create {output} {config} {mkdtimg_opts} -d {dtbo_staging_dir}
                  rm -rf {dtbo_staging_dir}
        """.format(
            output = output.path,
            srcs = " ".join([f.path for f in ctx.files.srcs]),
            config = ctx.file.config_file.path,
            dtbo_staging_dir = dtbo_staging_dir,
            mkdtimg_opts = mkdtimg_opts_cmd,
        )
    else:
        command += """
                # make dtbo
                  mkdtimg create {output} {mkdtimg_opts} {srcs}
        """.format(
            output = output.path,
            srcs = " ".join([f.path for f in ctx.files.srcs]),
            mkdtimg_opts = mkdtimg_opts_cmd,
        )

    debug.print_scripts(ctx, command)
    ctx.actions.run_shell(
        mnemonic = "DtboImage",
        inputs = depset(inputs, transitive = transitive_inputs),
        outputs = [output],
        tools = tools,
        progress_message = "Building dtbo image %{label}",
        command = command,
    )
    return DefaultInfo(files = depset([output]))

dtbo_image = rule(
    implementation = _dtbo_image_impl,
    doc = "Build dtbo image.",
    attrs = {
        "kernel_build": attr.label(
            mandatory = True,
            providers = [KernelSerializedEnvInfo, KernelBuildInfo],
            doc = "The [`kernel_build`](#kernel_build).",
        ),
        "opts": attr.string_list(
            doc = "Flags passed to `mkdtimg` tool. Successor of `MKDTIMG_FLAGS` ",
        ),
        "srcs": attr.label_list(
            allow_files = True,
            doc = """
                List of `*.dtbo` files used to package the `dtbo.img`. This corresponds to
                `MKDTIMG_DTBOS` in build configs; see example below.

                Example:
                ```
                kernel_build(
                    name = "tuna_kernel",
                    outs = [
                        "path/to/foo.dtbo",
                        "path/to/bar.dtbo",
                    ],
                )
                dtbo(
                    name = "tuna_images",
                    kernel_build = ":tuna_kernel",
                    srcs = [
                        ":tuna_kernel/path/to/foo.dtbo",
                        ":tuna_kernel/path/to/bar.dtbo",
                    ],
                )
                ```
            """,
        ),
        "config_file": attr.label(
            allow_single_file = True,
            doc = """A config file to create dtbo image by cfg_create command.

            If set, use mkdtimg cfg_create with the given config file, instead of mkdtimg create""",
        ),
        "_debug_print_scripts": attr.label(
            default = "//build/kernel/kleaf:debug_print_scripts",
        ),
        "out": attr.string(
            doc = """Name of the `dtbo` image.

            Default to `<name>/dtbo.img` if not set.
        """,
        ),
    },
    subrules = [
        utils.get_check_sandbox_cmd,
    ],
)
