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

load("@bazel_skylib//rules:select_file.bzl", "select_file")
load("@kernel_toolchain_info//:dict.bzl", "VARS")
load("@kleaf//build/kernel/kleaf/impl:cc.bzl", "resolved_clang_extractor")
load("@rules_cc//cc:cc_import.bzl", "cc_import")
load("@rules_rust//rust:toolchain.bzl", "rust_toolchain", "rustfmt_toolchain")
load("@rules_rust_bindgen//:defs.bzl", "rust_bindgen_toolchain")

_RUST_PKG = package_relative_label("@prebuilt_rust//" + VARS["RUSTC_VERSION"])

# Extract Rust binaries from prebuilt using bazel_skylib's select_file
select_file(
    name = "rustc_file",
    srcs = _RUST_PKG.same_package_label("binaries"),
    subpath = "bin/rustc",
)

select_file(
    name = "rustdoc_file",
    srcs = _RUST_PKG.same_package_label("binaries"),
    subpath = "bin/rustdoc",
)

select_file(
    name = "rustfmt_file",
    srcs = _RUST_PKG.same_package_label("binaries"),
    subpath = "bin/rustfmt",
)

# Toolchains

## Host glibc
rust_toolchain(
    name = "rust_toolchain_x86_64-unknown-linux-gnu",
    binary_ext = "",
    dylib_ext = ".so",
    exec_triple = "x86_64-unknown-linux-gnu",
    rust_doc = ":rustdoc_file",
    rust_std = _RUST_PKG.same_package_label("stdlib_x86_64-unknown-linux-gnu"),
    rustc = ":rustc_file",
    rustfmt = ":rustfmt_file",
    staticlib_ext = ".a",
    stdlib_linkflags = [],
    target_triple = "x86_64-unknown-linux-gnu",
)

toolchain(
    name = "2_x86_64-unknown-linux-gnu",
    exec_compatible_with = [
        "@platforms//os:linux",
        "@platforms//cpu:x86_64",
    ],
    target_compatible_with = [
        "@platforms//os:linux",
        "@platforms//cpu:x86_64",
    ],
    toolchain = ":rust_toolchain_x86_64-unknown-linux-gnu",
    toolchain_type = "@rules_rust//rust:toolchain_type",
    visibility = ["//visibility:public"],
)

## Host musl
rust_toolchain(
    name = "rust_toolchain_x86_64-unknown-linux-musl",
    binary_ext = "",
    dylib_ext = ".so",
    exec_triple = "x86_64-unknown-linux-gnu",
    rust_doc = ":rustdoc_file",
    rust_std = _RUST_PKG.same_package_label("stdlib_x86_64-unknown-linux-musl"),
    rustc = ":rustc_file",
    rustfmt = ":rustfmt_file",
    staticlib_ext = ".a",
    stdlib_linkflags = [],
    target_triple = "x86_64-unknown-linux-musl",
)

toolchain(
    name = "1_x86_64-unknown-linux-musl",
    exec_compatible_with = [
        "@platforms//os:linux",
        "@platforms//cpu:x86_64",
    ],
    target_compatible_with = [
        "@platforms//os:linux",
        "@platforms//cpu:x86_64",
        "@kleaf//build/kernel/kleaf/platforms/libc:musl",
    ],
    toolchain = ":rust_toolchain_x86_64-unknown-linux-musl",
    toolchain_type = "@rules_rust//rust:toolchain_type",
    visibility = ["//visibility:public"],
)

## Target Android ARM64
rust_toolchain(
    name = "rust_toolchain_aarch64-linux-android",
    binary_ext = "",
    dylib_ext = ".so",
    exec_triple = "x86_64-unknown-linux-gnu",
    rust_doc = ":rustdoc_file",
    rust_std = _RUST_PKG.same_package_label("stdlib_aarch64-linux-android"),
    rustc = ":rustc_file",
    rustfmt = ":rustfmt_file",
    staticlib_ext = ".a",
    stdlib_linkflags = [],
    target_triple = "aarch64-linux-android",
)

toolchain(
    name = "aarch64-linux-android",
    exec_compatible_with = [
        "@platforms//os:linux",
        "@platforms//cpu:x86_64",
    ],
    target_compatible_with = [
        "@platforms//os:android",
        "@platforms//cpu:arm64",
    ],
    toolchain = ":rust_toolchain_aarch64-linux-android",
    toolchain_type = "@rules_rust//rust:toolchain_type",
    visibility = ["//visibility:public"],
)

## Target Android RISCV64
rust_toolchain(
    name = "rust_toolchain_riscv64-linux-android",
    binary_ext = "",
    dylib_ext = ".so",
    exec_triple = "x86_64-unknown-linux-gnu",
    rust_doc = ":rustdoc_file",
    rust_std = _RUST_PKG.same_package_label("stdlib_riscv64-linux-android"),
    rustc = ":rustc_file",
    rustfmt = ":rustfmt_file",
    staticlib_ext = ".a",
    stdlib_linkflags = [],
    target_triple = "riscv64-linux-android",
)

toolchain(
    name = "riscv64-linux-android",
    exec_compatible_with = [
        "@platforms//os:linux",
        "@platforms//cpu:x86_64",
    ],
    target_compatible_with = [
        "@platforms//os:android",
        "@platforms//cpu:riscv64",
    ],
    toolchain = ":rust_toolchain_riscv64-linux-android",
    toolchain_type = "@rules_rust//rust:toolchain_type",
    visibility = ["//visibility:public"],
)

## Target Android X86_64
rust_toolchain(
    name = "rust_toolchain_x86_64-linux-android",
    binary_ext = "",
    dylib_ext = ".so",
    exec_triple = "x86_64-unknown-linux-gnu",
    rust_doc = ":rustdoc_file",
    rust_std = _RUST_PKG.same_package_label("stdlib_x86_64-linux-android"),
    rustc = ":rustc_file",
    rustfmt = ":rustfmt_file",
    staticlib_ext = ".a",
    stdlib_linkflags = [],
    target_triple = "x86_64-linux-android",
)

toolchain(
    name = "x86_64-linux-android",
    exec_compatible_with = [
        "@platforms//os:linux",
        "@platforms//cpu:x86_64",
    ],
    target_compatible_with = [
        "@platforms//os:android",
        "@platforms//cpu:x86_64",
    ],
    toolchain = ":rust_toolchain_x86_64-linux-android",
    toolchain_type = "@rules_rust//rust:toolchain_type",
    visibility = ["//visibility:public"],
)

# Rustfmt
rustfmt_toolchain(
    name = "rustfmt_impl",
    rustfmt = ":rustfmt_file",
)

toolchain(
    name = "rustfmt",
    exec_compatible_with = [
        "@platforms//os:linux",
        "@platforms//cpu:x86_64",
    ],
    toolchain = ":rustfmt_impl",
    toolchain_type = "@rules_rust//rust/rustfmt:toolchain_type",
    visibility = ["//visibility:public"],
)

# Bindgen

# Dynamically resolve and extract Clang libraries from the resolved CC toolchain in ONE pass
resolved_clang_extractor(
    name = "clang_extracted",
    filenames = [
        "libclang.so",
        "libc++.so",
    ],
)

# Use bazel_skylib's select_file to select the files directly from the extractor's outputs.
select_file(
    name = "libclang_file",
    srcs = ":clang_extracted",
    subpath = "libclang.so",
)

select_file(
    name = "libcxx_file",
    srcs = ":clang_extracted",
    subpath = "libc++.so",
)

cc_import(
    name = "libclang",
    shared_library = ":libclang_file",
)

cc_import(
    name = "libc++",
    shared_library = ":libcxx_file",
)

rust_bindgen_toolchain(
    name = "bindgen_toolchain_impl",
    bindgen = "@kleaf//build/kernel:bindgen",
    # clang is omitted because bindgen runs in-process via libclang.so and does
    # not need to spawn a compiler process. libclang.so successfully resolves
    # built-in headers (e.g. stddef.h) relative to its own path in the sandbox.
    libclang = ":libclang",
    libstdcxx = ":libc++",
)

toolchain(
    name = "bindgen",
    exec_compatible_with = [
        "@platforms//os:linux",
        "@platforms//cpu:x86_64",
    ],
    toolchain = ":bindgen_toolchain_impl",
    toolchain_type = "@rules_rust_bindgen//:toolchain_type",
    visibility = ["//visibility:public"],
)
