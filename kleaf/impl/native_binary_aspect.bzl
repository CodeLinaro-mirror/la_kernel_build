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

"""Inspect `native_binary`.

Though we generally discourage the use of aspects, aspects are needed here to avoid
reversed dependency from `//prebuilts/build-tools` to `//build/kernel` (in other words,
`//prebuilts/build-tools` remain Kleaf-agnostic.)
"""

visibility("private")

NativeBinaryAspectInfo = provider(
    doc = "Info of `native_binary_aspect`.",
    fields = {
        "executable": "the executable",
        "runfiles": "depset of runfiles",
    },
)

def _native_binary_aspect_impl(target, ctx):
    if ctx.rule.kind != "native_binary":
        return []
    if ctx.rule.attr.env:
        fail("{}: native_binary(env=) not yet supported in hermetic tools", target.label)

    this_data = depset(
        transitive = [target.files for target in ctx.rule.attr.data] +
                     [target[DefaultInfo].default_runfiles.files for target in ctx.rule.attr.data],
    )

    # If src is also a native_binary, propagate values. This ensures src is the inner most
    # one that is NOT a native_binary.
    # Intentionally leave out src[DefaultInfo].default_runfiles.files because that includes the
    # symlink, which we don't need.
    if NativeBinaryAspectInfo in ctx.rule.attr.src:
        return NativeBinaryAspectInfo(
            executable = ctx.rule.attr.src[NativeBinaryAspectInfo].executable,
            runfiles = depset(transitive = [this_data, ctx.rule.attr.src[NativeBinaryAspectInfo].runfiles]),
        )

    # Otherwise include src[DefaultInfo].default_runfiles.files in runfiles.

    # If src is an executable (e.g. a cc_binary or a py_binary), use its executable/runfiles
    if ctx.rule.attr.src[DefaultInfo].files_to_run and ctx.rule.attr.src[DefaultInfo].files_to_run.executable:
        return NativeBinaryAspectInfo(
            executable = ctx.rule.attr.src[DefaultInfo].files_to_run.executable,
            runfiles = depset(transitive = [this_data, ctx.rule.attr.src[DefaultInfo].default_runfiles.files]),
        )

    # Otherwise, expect that src is a single file and use it as the executable.
    files = ctx.rule.attr.src[DefaultInfo].files.to_list()
    if not len(files) == 1:
        fail("{}: native_binary(src=) has multiple files, which is not supported", target.label)

    return NativeBinaryAspectInfo(
        executable = files[0],
        runfiles = depset(transitive = [this_data, ctx.rule.attr.src[DefaultInfo].default_runfiles.files]),
    )

native_binary_aspect = aspect(
    doc = """Turn `native_binary` into an `executable_dispatcher`-like target,
        so that ctx.actions.symlink() is avoided.""",
    implementation = _native_binary_aspect_impl,
    attr_aspects = [
        "src",
        "data",
        "env",
    ],
)
