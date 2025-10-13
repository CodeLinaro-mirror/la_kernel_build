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

load("//build/kernel/kleaf:hermetic_tools.bzl", "hermetic_toolchain")
load(":debug.bzl", "debug")
load(":utils.bzl", "utils")

visibility("//build/kernel/kleaf/...")

def _dtbo_image_impl(ctx):
    hermetic_tools = hermetic_toolchain.get(ctx)
    command = hermetic_tools.setup

    out_name = ctx.attr.out or (ctx.label.name + "/dtbo.img")
    output = ctx.actions.declare_file(out_name)
    dtbo_staging_dir = output.dirname + "/staging"
    inputs = []
    transitive_inputs = [target.files for target in ctx.attr.srcs]

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
            mkdtimg_opts = " ".join(ctx.attr.opts),
        )
    else:
        command += """
                # make dtbo
                  mkdtimg create {output} {mkdtimg_opts} {srcs}
        """.format(
            output = output.path,
            srcs = " ".join([f.path for f in ctx.files.srcs]),
            mkdtimg_opts = " ".join(ctx.attr.opts),
        )

    debug.print_scripts(ctx, command)
    ctx.actions.run_shell(
        mnemonic = "DtboImage",
        inputs = depset(inputs, transitive = transitive_inputs),
        outputs = [output],
        tools = hermetic_tools.deps,
        progress_message = "Building dtbo image %{label}",
        command = command,
    )
    return DefaultInfo(files = depset([output]))

dtbo_image = rule(
    implementation = _dtbo_image_impl,
    doc = """Build `dtb` or `dtbo` partition image.

        The partition image contains a `dt_table_entry` table header, as specified in
        [DTB and DTBO partitions](https://source.android.com/docs/core/architecture/dto/partitions).

        **Note**: Despite the name, this can be used to build the `dtb` **partition** image.
        However, it is not for concatenated DT blobs (`*.dtb`) embedded in the `boot` or
        `vendor_boot` image. Use [`dtb_image`](#dtb_image) for that purpose.
    """,
    attrs = {
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
    toolchains = [
        hermetic_toolchain.type,
    ],
)
