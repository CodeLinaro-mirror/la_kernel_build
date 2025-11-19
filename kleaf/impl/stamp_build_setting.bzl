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

"""Helper rule to get the value of --stamp.

https://github.com/bazelbuild/bazel/issues/11164
"""

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")

visibility("private")

def _stamp_build_setting_impl(ctx):
    return BuildSettingInfo(value = ctx.attr.value)

stamp_build_setting = rule(
    doc = "Helper to get the value of --stamp",
    implementation = _stamp_build_setting_impl,
    attrs = {
        "value": attr.bool(
            mandatory = True,
        ),
    },
)
