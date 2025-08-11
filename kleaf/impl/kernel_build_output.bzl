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

"""Picks an output file from kernel_build."""

visibility("//build/kernel/...")

def _kernel_build_output_impl(
        name,
        kernel_build,
        out,
        visibility,
        **kwargs):
    # Wrap the configurable kernel_build in an alias so we can put it in the srcs list below.
    native.alias(
        name = name + "_kernel_build",
        actual = kernel_build,
        visibility = ["//visibility:private"],
        **kwargs
    )

    native.filegroup(
        name = name,
        srcs = [name + "_kernel_build"],
        output_group = out,
        visibility = visibility,
        **kwargs
    )

kernel_build_output = macro(
    doc = """Picks an output file from kernel_build.

        When `generate_out_targets = False` for a kernel_build, especially
        when its `*outs` attributes are set to a select() expression, the
        `<kernel_build_name>/<out>` label is not created. These attributes are:

        *   outs
        *   module_outs
        *   module_implicit_outs
        *   implicit_outs

        To create the proper label, use this helper macro.

        Example:

        ```
        kernel_build(
            name = "foo",
            generate_out_targets = False,
            module_outs = select({
                ":my_config_setting": ["some_module.ko"],
                "//conditions:default": [],
            }) + [
                "common_module.ko",
            ],
        )
        ```

        Because `module_outs` is a select expression, the macro cannot
        infer its value during macro expansion. To create labels to these
        in-tree modules, declare the following:

        ```
        kernel_build_output(
            name = "foo/some_module.ko",
            kernel_build = ":foo",
            out = "some_module.ko",
        )
        kernel_build_output(
            name = "foo/common_module.ko",
            kernel_build = ":foo",
            out = "common_module.ko",
        )
        ```

        In the above example, if `:my_config_setting` does not apply, the
        `foo/some_module.ko` target will not contain any files.
    """,
    implementation = _kernel_build_output_impl,
    attrs = {
        "kernel_build": attr.label(mandatory = True),
        "out": attr.string(mandatory = True),
    },
)
