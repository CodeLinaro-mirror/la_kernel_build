# Copyright (C) 2024 The Android Open Source Project
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

"""`bison` and `flex` wrapper.

Caveat: Do not use native_binary or ctx.actions.symlink() to wrap this binary
due to the use of $0.
"""

load("@bazel_skylib//lib:paths.bzl", "paths")

visibility("//build/kernel/...")

def _bison_flex_wrapper_impl(ctx):
    # TODO: path calculations requires this level because of the ctx.actions.symlink()
    # in hermetic_tools(). This needs to be fixed.
    file = ctx.actions.declare_file(ctx.attr.name + "/" + ctx.attr.name)
    root_from_base = "/".join([".."] * len(paths.dirname(file.path).split("/")))

    set_pkgdatadir_cmd = ""
    if ctx.file.pkgdata_dir:
        if not ctx.attr.name == "bison":
            fail("pkgdata_dir only supported for bison wrapper")
        set_pkgdatadir_cmd = """
            if [ -n "${{BUILD_WORKSPACE_DIRECTORY}}" ] || [ "${{BAZEL_TEST}}" = "1" ] || [ -d ${{RUNFILES_DIR:-${{0}}.runfiles}} ]; then
                export BISON_PKGDATADIR=${{RUNFILES_DIR}}/{workspace_name}/{pkgdata_dir_short}
            else
                export BISON_PKGDATADIR=${{KLEAF_REPO_DIR}}/{pkgdata_dir}
            fi
            if [ ! -d "${{BISON_PKGDATADIR}}" ]; then
                echo "ERROR: BISON_PKGDATADIR ${{BISON_PKGDATADIR}} is empty!" >&2
                exit 1
            fi
        """.format(
            workspace_name = ctx.workspace_name,
            pkgdata_dir_short = ctx.file.pkgdata_dir.short_path,
            pkgdata_dir = ctx.file.pkgdata_dir.path,
        )

    content = """\
#!/bin/sh

# We don't use any tools in this script. Prevent using host tools.
PATH=

if [ -n "${{BUILD_WORKSPACE_DIRECTORY}}" ] || [ "${{BAZEL_TEST}}" = "1" ] || [ -d ${{RUNFILES_DIR:-${{0}}.runfiles}} ]; then
    export RUNFILES_DIR=${{RUNFILES_DIR:-${{0}}.runfiles}}
    ACTUAL=${{RUNFILES_DIR}}/{workspace_name}/{actual_short}
    export M4=${{RUNFILES_DIR}}/{workspace_name}/{m4_short}
else
    KLEAF_REPO_DIR=${{0%/*}}/{root_from_base}
    ACTUAL=${{KLEAF_REPO_DIR}}/{actual}
    export M4=${{KLEAF_REPO_DIR}}/{m4}
fi

if [ ! -x "${{M4}}" ]; then
    echo "ERROR: m4 is not found at ${{M4}}" >&2
    exit 1
fi

{set_pkgdatadir_cmd}

"${{ACTUAL}}" $*
""".format(
        # https://bazel.build/extending/rules#runfiles_location
        # The recommended way to detect launcher_path is use $0.
        # From man sh: If bash is invoked with a file of commands, $0 is set to the name of that
        # file.
        workspace_name = ctx.workspace_name,
        root_from_base = root_from_base,
        actual = ctx.executable.actual.path,
        m4 = ctx.executable.m4.path,
        actual_short = ctx.executable.actual.short_path,
        m4_short = ctx.executable.m4.short_path,
        set_pkgdatadir_cmd = set_pkgdatadir_cmd,
    )
    ctx.actions.write(file, content, is_executable = True)

    return DefaultInfo(
        files = depset([file]),
        runfiles = ctx.runfiles(
            files = [ctx.executable.actual],
            transitive_files = ctx.attr.pkgdata_files.files if ctx.attr.pkgdata_files else depset(),
        ).merge_all([
            ctx.attr.actual[DefaultInfo].default_runfiles,
            ctx.attr.m4[DefaultInfo].default_runfiles,
        ]),
        executable = file,
    )

bison_flex_wrapper = rule(
    implementation = _bison_flex_wrapper_impl,
    doc = """Creates a wrapper script over real `bison` / `flex` binary.

        Caveat: Do not use native_binary or ctx.actions.symlink() to wrap this binary
        due to the use of $0.
    """,
    attrs = {
        "actual": attr.label(
            allow_files = True,
            executable = True,
            # Don't apply transitions; let hermetic_tools handle it.
            cfg = "target",
        ),
        "pkgdata_dir": attr.label(allow_single_file = True),
        "pkgdata_files": attr.label(allow_files = True),
        "m4": attr.label(
            executable = True,
            # Don't apply transitions; let hermetic_tools handle it.
            cfg = "target",
        ),
    },
    executable = True,
)
