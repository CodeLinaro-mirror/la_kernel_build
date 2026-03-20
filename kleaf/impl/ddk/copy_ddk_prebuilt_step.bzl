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

"""Creates a step that copies a prebuilt."""

visibility("//build/kernel/kleaf/...")

def _copy_ddk_prebuilt_step_impl(subrule_ctx, hermetic_tools, source, target, what):
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

copy_ddk_prebuilt_step = subrule(
    implementation = _copy_ddk_prebuilt_step_impl,
)
