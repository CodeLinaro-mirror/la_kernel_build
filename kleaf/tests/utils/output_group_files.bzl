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

"""Selects an output group from a target without forwarding runfiles."""

visibility("//build/kernel/kleaf/tests/...")

def _output_group_files_impl(ctx):
    return DefaultInfo(
        files = ctx.attr.src[OutputGroupInfo][ctx.attr.output_group],
    )

output_group_files = rule(
    doc = """Selects files from an output group of `src` as default outputs.

Unlike `native.filegroup(output_group = ...)`, this rule does not forward
`data_runfiles` from `src` when consumed via `data` attributes (see
`--incompatible_filegroup_runfiles_for_data`).
""",
    implementation = _output_group_files_impl,
    attrs = {
        "output_group": attr.string(
            mandatory = True,
            doc = "Name of the output group in `OutputGroupInfo`.",
        ),
        "src": attr.label(
            mandatory = True,
            providers = [OutputGroupInfo],
            doc = "Target providing `OutputGroupInfo`.",
        ),
    },
)
