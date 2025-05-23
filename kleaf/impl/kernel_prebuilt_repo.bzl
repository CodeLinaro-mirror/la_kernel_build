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

"""Repository for kernel prebuilts."""

load(
    ":constants.bzl",
    "FILEGROUP_DEF_ARCHIVE_SUFFIX",
    "FILEGROUP_DEF_BUILD_FRAGMENT_NAME",
)

visibility("//build/kernel/kleaf/...")

def _get_local_path(repository_ctx, local_filename):
    """Returns a path object where we store the file named local_filename"""
    return repository_ctx.path(_join(local_filename, _basename(local_filename)))

def _symlink_local_file(repository_ctx, local_filename, file_mandatory):
    """Creates symlink in local_filename that points to remote_filename.

    Returns:
        True if the file exist, false if the file does not exist and is not
        mandatory, otherwise fail().
    """

    local_path = _get_local_path(repository_ctx, local_filename)

    artifact_path = repository_ctx.workspace_root.get_child(repository_ctx.attr.local_artifact_path).get_child(local_filename)
    if artifact_path.exists:
        repository_ctx.symlink(artifact_path, local_path)
        return True
    if file_mandatory:
        fail("{}: {} does not exist".format(repository_ctx.attr.name, artifact_path))
    return False

def _get_ci_target_mapping(repository_ctx):
    path = repository_ctx.workspace_root.get_child(repository_ctx.attr.local_artifact_path).get_child("ci_target_mapping.json")
    content = repository_ctx.read(path)
    return json.decode(content)

def _kernel_prebuilt_repo_impl(repository_ctx):
    ci_target_mapping = _get_ci_target_mapping(repository_ctx)

    results = {}
    for local_filename, config in ci_target_mapping.get("download_configs", {}).items():
        results[local_filename] = _symlink_local_file(
            repository_ctx = repository_ctx,
            local_filename = local_filename,
            file_mandatory = config["mandatory"],
        )

    for local_filename, result in results.items():
        if result:
            fmt = """\
exports_files(
    [{local_filename_repr}],
    visibility = ["//visibility:public"],
)
"""
        else:
            fmt = """\
filegroup(
    name = {local_filename_repr},
    srcs = [],
    visibility = ["//visibility:public"],
)
"""
        content = fmt.format(
            local_filename_repr = repr(_basename(local_filename)),
            fail_bzl = Label("//build/kernel/kleaf:fail.bzl"),
        )
        repository_ctx.file(_join(local_filename, "BUILD.bazel"), content)

    _create_top_level_files(repository_ctx, ci_target_mapping)

def _create_top_level_files(repository_ctx, ci_target_mapping):
    bazel_target_name = repository_ctx.attr.target
    repository_ctx.file("""WORKSPACE.bazel""", """\
workspace({})
""".format(repr(repository_ctx.attr.name)))

    filegroup_decl_archives = []
    for local_filename in ci_target_mapping.get("download_configs", {}):
        if _basename(local_filename).endswith(FILEGROUP_DEF_ARCHIVE_SUFFIX):
            local_path = repository_ctx.path(_join(local_filename, _basename(local_filename)))
            filegroup_decl_archives.append(local_path)

    if not filegroup_decl_archives:
        return
    if len(filegroup_decl_archives) > 1:
        fail("Multiple files with suffix {}: {}".format(
            FILEGROUP_DEF_ARCHIVE_SUFFIX,
            filegroup_decl_archives,
        ))

    filegroup_decl_archive = filegroup_decl_archives[0]
    repository_ctx.extract(
        # If local_artifact_path is set, filegroup_decl_archive is a symlink.
        # The symlink is under the working directory so we can't set
        # watch_archive = "yes".
        # Use realpath (which may point outside the working directory) and
        # watch_archive = "auto" (the default) achieves optimal effect.
        archive = filegroup_decl_archive.realpath,
        output = repository_ctx.path(bazel_target_name),
    )

    template_path = repository_ctx.path(_join(bazel_target_name, FILEGROUP_DEF_BUILD_FRAGMENT_NAME))
    template_content = repository_ctx.read(template_path)

    repository_ctx.file(repository_ctx.path(_join(bazel_target_name, "BUILD.bazel")), """\
load({kernel_bzl_repr}, "kernel_filegroup")
load({extracted_gki_artifacts_archive_bzl_repr}, "extracted_gki_artifacts_archive")
load({extracted_system_dlkm_staging_archive_bzl_repr}, "extracted_system_dlkm_staging_archive")

_CLANG_KLEAF_PKG = {clang_kleaf_pkg}

{template_content}
""".format(
        kernel_bzl_repr = repr(str(Label("//build/kernel/kleaf:kernel.bzl"))),
        extracted_gki_artifacts_archive_bzl_repr = repr(str(Label(":extracted_gki_artifacts_archive.bzl"))),
        extracted_system_dlkm_staging_archive_bzl_repr = repr(str(Label(":extracted_system_dlkm_staging_archive.bzl"))),
        clang_kleaf_pkg = repr(str(Label("//prebuilts/clang/host/linux-x86/kleaf"))),
        template_content = template_content,
    ))

kernel_prebuilt_repo = repository_rule(
    implementation = _kernel_prebuilt_repo_impl,
    attrs = {
        "local_artifact_path": attr.string(
            doc = """Directory to local artifacts.

                If set, `artifact_url_fmt` is ignored.

                Only the root module may call `declare()` with this attribute set.

                If relative, it is interpreted against workspace root.

                If absolute, this is similar to setting `artifact_url_fmt` to
                `file://<absolute local_artifact_path>/{filename}`, but avoids
                using `download()`. Files are symlinked not copied, and
                `--config=internet` is not necessary.
            """,
            mandatory = True,
        ),
        "apparent_name": attr.string(doc = "apparant repo name", mandatory = True),
        "target": attr.string(doc = "Name of target on the download location, e.g. `kernel_aarch64`"),
    },
)

# Avoid dependency to paths, since we do not necessary have skylib loaded yet.
# TODO(b/276493276): Use paths once we migrate to bzlmod completely.
def _basename(s):
    return s.split("/")[-1]

def _join(path, *others):
    ret = path

    for other in others:
        if not ret.endswith("/"):
            ret += "/"
        ret += other

    return ret
