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

"""A target that configures a [`ddk_module`](#ddk_module)."""

load(":utils.bzl", "kernel_utils", "utils")

visibility("private")

def _extract_dot_config_impl(subrule_ctx, serialized_env_info):
    dot_config = subrule_ctx.actions.declare_file("{name}/.config".format(name = subrule_ctx.label.name))
    command = kernel_utils.setup_serialized_env_cmd(
        serialized_env_info = serialized_env_info,
        restore_out_dir_cmd = utils.get_check_sandbox_cmd(),
    )
    command += """
        rsync -aL ${{OUT_DIR}}/.config {dot_config}
    """.format(
        dot_config = dot_config.path,
    )
    subrule_ctx.actions.run_shell(
        command = command,
        outputs = [dot_config],
        tools = serialized_env_info.tools,
        inputs = serialized_env_info.inputs,
        mnemonic = "DdkModuleConfigDotConfig",
        progress_message = "Extracting .config %{label}",
    )
    return dot_config

extract_dot_config = subrule(
    implementation = _extract_dot_config_impl,
    subrules = [utils.get_check_sandbox_cmd],
)
