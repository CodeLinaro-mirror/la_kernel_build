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

load(":local_repository.bzl", "get_kleaf_repo_dir")

visibility("private")

_CANDIDATES = [
    # do not sort
    ("prebuilts/rust-toolchain/linux-x86", "x86_64-unknown-linux-gnu"),
    ("prebuilts/rust-toolchain/linux-musl-x86", "x86_64-unknown-linux-musl"),
]

def _rust_toolchain_repository_impl(repository_ctx):
    kleaf_repo_dir = get_kleaf_repo_dir(repository_ctx)
    target = None
    exec_triple = None
    for candidate_path, candidate_triple in _CANDIDATES:
        # watch all candidates
        candidate_target = kleaf_repo_dir.get_child(candidate_path)
        repository_ctx.watch(candidate_target)

        # pick the first one that exists
        if candidate_target.exists and not target:
            target = candidate_target
            exec_triple = candidate_triple

    if target:
        # https://github.com/bazelbuild/bazel/issues/30883: Not calling readdir() but symlinking
        # the directory as a whole
        repository_ctx.symlink(target, repository_ctx.path("toolchain"))
    else:
        # Possible on repos without Rust (e.g. u-boot). Ignore -- don't even create the symlink.
        pass

    # Mark the repository boundary for Bzlmod
    repository_ctx.file("REPO.bazel", "")

    # Write constants to be loaded by BUILD.bazel
    repository_ctx.file("constants.scl", """\
visibility("private")
EXEC_TRIPLE = {exec_triple}
""".format(
        exec_triple = repr(exec_triple),
    ))

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
