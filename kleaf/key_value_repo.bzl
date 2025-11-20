"""Turn a simple build.config into a Bazel extension."""

def _parse_file(raw_content):
    ret = {}
    for line in raw_content.splitlines():
        key, value = line.split("=", 1)
        if value.startswith('"') and value.endswith('"'):
            value = value[1:-1]
        ret[key.strip()] = value.strip()
    return ret

def _impl(repository_ctx):
    all_vars = {}

    use_fallback = False
    for src in repository_ctx.attr.srcs:
        if not repository_ctx.path(src).exists:
            use_fallback = True
            continue
        all_vars.update(_parse_file(repository_ctx.read(src)))

    if use_fallback:
        if not repository_ctx.attr.internal_fallback_src:
            fail("One of the following does not exist: {}".format(repository_ctx.attr.srcs))

        # buildifier: disable=print
        print("""\
WARNING: {} is deprecated. Copy or symlink it to {} instead.""".format(
            repository_ctx.attr.internal_fallback_src,
            repository_ctx.attr.srcs[0],
        ))
        all_vars.update(_parse_file(repository_ctx.read(repository_ctx.attr.internal_fallback_src)))

    repository_content = ""
    for key, value in all_vars.items():
        repository_content += '{} = "{}"\n'.format(key, value)
    for key, value in repository_ctx.attr.additional_values.items():
        repository_content += '{} = "{}"\n'.format(key, value)

    if "VARS" in all_vars:
        fail("{}: VARS is a reserved variable name.".format(repository_ctx.attr.name))

    repository_content += "VARS = " + repr(all_vars) + "\n"

    repository_ctx.file("BUILD", """
load("@bazel_skylib//:bzl_library.bzl", "bzl_library")
bzl_library(
    name = "dict",
    srcs = ["dict.bzl"],
    visibility = ["//visibility:public"],
)
""", executable = False)
    repository_ctx.file("dict.bzl", repository_content, executable = False)

key_value_repo = repository_rule(
    implementation = _impl,
    local = True,
    doc = """Exposes a Bazel repository with key value pairs defined from srcs.

Configuration files shall contain a single pair of key and value separated
by '='. Keys and values are stripped, hence whitespace characters around the
separator are allowed.

Example:
Given a file `common/bazel/constants.scl` with content
```
    CLANG_VERSION=r433403
```

The workspace file can instantiate a repository rule with
```
load("//build/kernel/kleaf:key_value_repo.bzl", "key_value_repo")

key_value_repo(
    name = "kernel_toolchain_info",
    srcs = ["//common:bazel/constants.scl"],
)
```

and users of the repository can refer to the values with
```
load("@kernel_toolchain_info//:dict.bzl", "CLANG_VERSION")
```
""",
    attrs = {
        "srcs": attr.label_list(
            mandatory = True,
            doc = """Configuration files storing `key=value` or `key="value"` pairs.""",
        ),
        "additional_values": attr.string_dict(
            doc = "Additional values in `dict.bzl`",
        ),
        "internal_fallback_src": attr.label(
            doc = "**INTERNAL ONLY**; fallback src file.",
        ),
    },
)
