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

load("@bazel_skylib//lib:paths.bzl", "paths")

_TRIPLES = [paths.basename(path) for path in glob(
    ["toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/*"],
    exclude_directories = 0,
)]

_LEVELS_FOR_TRIPLE = {
    triple: [
        int(paths.basename(path))
        for path in glob(
            ["toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/{}/*".format(triple)],
            exclude_directories = 0,
        )
        if paths.basename(path).isdigit()
    ]
    for triple in _TRIPLES
}

_SYSROOT_TRIPLE_COMMON_FILES = [
    "libc.a",
    "libdl.a",
    "libm.a",
]

_SYSROOT_TRIPLE_LEVEL_FILES = [
    "libc.so",
    "libdl.so",
    "libm.so",
    "crtbegin_dynamic.o",
    "crtbegin_static.o",
    "crtend_android.o",
    "crtbegin_so.o",
    "crtend_so.o",
]

filegroup(
    name = "sysroot_dir",
    srcs = ["toolchains/llvm/prebuilt/linux-x86_64/sysroot"],
    visibility = ["@kleaf_clang_toolchain//:__subpackages__"],
)

filegroup(
    name = "sysroot_include",
    srcs = glob(
        ["toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/include/**"],
        allow_empty = False,
    ),
    visibility = ["//visibility:private"],
)

[filegroup(
    name = "sysroot_{}_common".format(triple),
    srcs = [
        "toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/{}/{}".format(triple, filename)
        for filename in _SYSROOT_TRIPLE_COMMON_FILES
    ],
    visibility = ["//visibility:private"],
) for triple in _TRIPLES]

[filegroup(
    name = "sysroot_{}{}_files".format(triple, level),
    srcs = [
        "toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/{}/{}/{}".format(triple, level, filename)
        for filename in _SYSROOT_TRIPLE_LEVEL_FILES
    ] + [
        ":sysroot_{}_common".format(triple),
        ":sysroot_include",
    ],
    visibility = ["@kleaf_clang_toolchain//:__subpackages__"],
) for triple in _TRIPLES for level in _LEVELS_FOR_TRIPLE[triple]]

[
    alias(
        name = "sysroot_armv7a-linux-androideabi{}_files".format(level),
        actual = "sysroot_arm-linux-androideabi{}_files".format(level),
        visibility = ["@kleaf_clang_toolchain//:__subpackages__"],
    )
    for level in _LEVELS_FOR_TRIPLE["arm-linux-androideabi"]
    if "arm-linux-androideabi" in _TRIPLES and
       "armv7a-linux-androideabi" not in _TRIPLES and
       # Android 9, CDD-3.3.2-C-3-1
       # If device implementations report the support of the armeabi ABI, they
       # MUST also support armeabi-v7a and report its support, as armeabi is only for backwards
       # compatibility with older apps.
       level >= 29
]
