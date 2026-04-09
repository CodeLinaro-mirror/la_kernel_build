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
"""
Defines macros to build libdwarves and pahole.
"""

load("@bazel_skylib//rules:write_file.bzl", "write_file")
load("@rules_cc//cc:cc_binary.bzl", "cc_binary")
load("@rules_cc//cc:cc_library.bzl", "cc_library")

def _pahole_impl(name, deps, visibility):
    """Defines libdwarves and pahole targets.

    Args:
        name: Name of the pahole binary.
        deps: Dependencies for building libdwarves.
        visibility: Visibility of libdwarves and pahole.
    """
    write_file(
        name = name + "_generated_config_h",
        out = "config.h",
        content = [
            "#define DWARVES_MAJOR_VERSION 1",
            "#define DWARVES_MINOR_VERSION 31",
            "#define HAVE_DWFL_MODULE_BUILD_ID 1",
            "#define HAVE_BPF_BTF_TYPE_TAG_RECURSIVE 1",
            "#define HAVE_BPF_BTF_FLOAT 1",
            "#define HAVE_BPF_BTF_DECL_TAG 1",
            "#define HAVE_BPF_ENUM64 1",
            "#define HAVE_BPF_BTF_TYPE_TAG 1",
            "",
        ],
    )

    cc_library(
        name = name + "_libdwarves",
        srcs = [
            "@dwarves//:libdwarves_sources",
            ":" + name + "_generated_config_h",
        ],
        hdrs = ["@dwarves//:libdwarves_headers"],
        copts = [
            "-D_GNU_SOURCE",
            "-Wno-deprecated-declarations",
            "-Wno-pointer-arith",
            "-Wno-unused-parameter",
            "-Wno-unused-variable",
        ],
        includes = ["."],
        deps = [
            Label("//prebuilts/kernel-build-tools:imported_libs"),
            "@argp-standalone//:argp",
            "@obstack",
        ] + deps,
    )

    cc_binary(
        name = name,
        srcs = ["@dwarves//:pahole_sources"],
        linkstatic = False,
        deps = [
            ":" + name + "_libdwarves",
        ],
        visibility = visibility,
    )

pahole = macro(
    attrs = {
        "deps": attr.label_list(
            mandatory = True,
            doc = "Dependencies for building libdwarves",
        ),
    },
    implementation = _pahole_impl,
)
