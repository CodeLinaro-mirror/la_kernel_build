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

"""Defines a repository that provides Rust toolchains."""

visibility("private")

def _rust_toolchain_repository_impl(repository_ctx):
    # Mark the repository boundary for Bzlmod
    repository_ctx.file("REPO.bazel", "")

    # Read the BUILD file template from the main repository
    build_content = repository_ctx.read(repository_ctx.attr._build_file)

    # Write it to the repository's BUILD.bazel
    repository_ctx.file("BUILD.bazel", build_content)

rust_toolchain_repository = repository_rule(
    implementation = _rust_toolchain_repository_impl,
    attrs = {
        "_build_file": attr.label(
            default = Label("//build/kernel/kleaf/impl:rust_toolchain_repository.BUILD"),
        ),
    },
    doc = "Repository rule that generates @kleaf_rust_toolchain.",
)
