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

"""Provides subrules that copy prebuilts to proper directories."""

load("//build/kernel/kleaf:directory_with_structure.bzl", dws = "directory_with_structure")

visibility("//build/kernel/kleaf/...")

def _copy_ddk_prebuilt_impl(subrule_ctx, hermetic_tools, source, target, what):
    """Creates an action that copies a single DDK prebuilt file.

    Args:
        subrule_ctx: The context of the subrule.
        hermetic_tools: A struct containing tools for hermetic execution.
        source: The source file to copy.
        target: The path for the destination file.
        what: A string to differentiate the mnemonic.
    """
    target = subrule_ctx.actions.declare_file(target)
    command = hermetic_tools.setup + """
        cp -aL {source} {target}
    """.format(
        source = source.path,
        target = target.path,
    )
    subrule_ctx.actions.run_shell(
        command = command,
        inputs = [source],
        outputs = [target],
        tools = hermetic_tools.deps,
        mnemonic = "CopyDdkPrebuilt" + what,
        progress_message = "Copying {} %{{label}}".format(source.basename),
    )
    return target

copy_ddk_prebuilt = subrule(
    implementation = _copy_ddk_prebuilt_impl,
)

def _copy_prebuilts_to_staging_impl(
        subrule_ctx,
        hermetic_tools,
        files,
        kernel_release_file,
        ext_mod):
    """Copies multiple prebuilt files into a staging directory structure.

    The files are copied into a directory structure like:
    <label_name>/staging/lib/modules/<kernel_release>/extra/<ext_mod>/

    Args:
        subrule_ctx: The context of the subrule.
        hermetic_tools: A struct containing tools for hermetic execution.
        files: A list of files to copy.
        kernel_release_file: The kernel release file.
        ext_mod: The name of the external module.
    Returns:
        A directory_with_structure representing the staging area.
    """
    modules_staging_dws = dws.make(subrule_ctx, "{}/staging".format(subrule_ctx.label.name))
    command = hermetic_tools.setup + """
        kernel_release=$(cat {kernel_release_file})
        mkdir -p {modules_staging_dir}/lib/modules/${{kernel_release}}/extra/{ext_mod}
        cp -aL {files} {modules_staging_dir}/lib/modules/${{kernel_release}}/extra/{ext_mod}
    """.format(
        files = " ".join([f.path for f in files]),
        modules_staging_dir = modules_staging_dws.directory.path,
        kernel_release_file = kernel_release_file.path,
        directory = modules_staging_dws.directory.path,
        ext_mod = ext_mod,
    )
    command += dws.record(modules_staging_dws)
    subrule_ctx.actions.run_shell(
        command = command,
        inputs = files + [kernel_release_file],
        outputs = [] + dws.files(modules_staging_dws),
        tools = hermetic_tools.deps,
        mnemonic = "CopyDdkPrebuiltToStaging",
        progress_message = "Copying prebuilt files to staging %{{label}}",
    )
    return modules_staging_dws

copy_prebuilts_to_staging = subrule(
    implementation = _copy_prebuilts_to_staging_impl,
)
