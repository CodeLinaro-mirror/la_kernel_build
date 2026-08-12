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

load("@protobuf//bazel:cc_proto_library.bzl", "cc_proto_library")
load("@protobuf//bazel:proto_library.bzl", "proto_library")
load("@rules_cc//cc:cc_binary.bzl", "cc_binary")
load("@rules_cc//cc:cc_library.bzl", "cc_library")

_COPTS = [
    "-std=c++20",
    "-fstrict-enums",
    "-Wall",
    "-Wextra",
]

proto_library(
    name = "stg_proto",
    srcs = ["stg.proto"],
)

cc_proto_library(
    name = "stg_cc_proto",
    deps = [":stg_proto"],
)

cc_library(
    name = "libstg",
    srcs = glob(
        ["*.cc"],
        exclude = [
            "stg.cc",
            "stgdiff.cc",
            "*_test.cc",
            "catch.cc",
        ],
    ),
    hdrs = glob(["*.h"]),
    copts = _COPTS,
    visibility = ["//visibility:public"],
    deps = [
        ":stg_cc_proto",
        "@kleaf//prebuilts/kernel-build-tools:imported_libs",
    ],
)

cc_binary(
    name = "stg",
    srcs = ["stg.cc"],
    copts = _COPTS,
    linkstatic = False,
    visibility = ["//visibility:public"],
    deps = [":libstg"],
)

cc_binary(
    name = "stgdiff",
    srcs = ["stgdiff.cc"],
    copts = _COPTS,
    linkstatic = False,
    visibility = ["//visibility:public"],
    deps = [":libstg"],
)
