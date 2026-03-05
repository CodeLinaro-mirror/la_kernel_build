# Copyright (C) 2024 The Android Open Source Project
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

"""RBE-friendly native_binary() that supports embedding args and env."""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("@rules_cc//cc:cc_binary.bzl", "cc_binary")
load(":utils.bzl", "utils")

visibility("//build/kernel/...")

def _get_single_executable(ctx, target):
    if target[DefaultInfo].files_to_run.executable:
        return target[DefaultInfo].files_to_run.executable

    # Hack for python_runtime_files()
    label = ctx.label.same_package_label(ctx.attr.name)
    files_list = target.files.to_list()
    if len(files_list) != 1:
        fail("{}: {} does not contain a single file: {}".format(
            label,
            target.label,
            files_list,
        ))
    return files_list[0]

def _write_source_file_impl(ctx):
    out = ctx.actions.declare_file(ctx.attr.source_name or ctx.label.name)
    actual_executable = _get_single_executable(ctx, ctx.attr.actual_executable)

    # This is not a perfect translation, but it is good enough for our use cases.
    append_args_str = json.encode(ctx.attr.append_args)

    # Drop the leading [ and trailing ]
    if not append_args_str.startswith("[") or not append_args_str.endswith("]"):
        fail("{} is translated to {}, but a list is expected".format(
            ctx.attr.append_args,
            append_args_str,
        ))
    append_args_str = append_args_str[1:len(append_args_str) - 1]

    env = {var_name: target for target, var_name in ctx.attr.reversed_env.items()}
    env_str = ""
    env_short_str = ""
    for var_name, target in env.items():
        file = utils.single_file(target.files.to_list(), target.label)
        env_str += "{{{}, {}}},".format(repr(var_name), repr(file.path))
        env_short_str += "{{{}, {}}},".format(repr(var_name), repr(file.short_path))

    ctx.actions.expand_template(
        template = ctx.file.template,
        output = out,
        substitutions = {
            "{actual_executable_path}": actual_executable.path,
            "{actual_executable_short_path}": actual_executable.short_path,
            "{append_args}": append_args_str,
            "{env}": env_str,
            "{env_short}": env_short_str,
            "{out}": ctx.attr.out,
            "{pkg_bin_dir}": utils.package_bin_dir(ctx),
            "{pkg_short}": paths.join(
                ctx.label.workspace_root,
                ctx.label.package,
            ),
        },
    )
    return DefaultInfo(files = depset([out]))

_write_source_file = rule(
    implementation = _write_source_file_impl,
    attrs = {
        "template": attr.label(mandatory = True, allow_single_file = True),
        "substitutions": attr.string_dict(),
        "actual_executable": attr.label(
            cfg = "target",
            allow_files = True,
        ),
        "append_args": attr.string_list(),
        "reversed_env": attr.label_keyed_string_dict(
            allow_files = True,
        ),
        "out": attr.string(),
        "source_name": attr.string(),
    },
)

def _executable_dispatcher_impl(
        name,
        visibility,
        src,
        out,
        data,
        append_args,
        reversed_env,
        internal_dispatcher_source_name,
        **kwargs):
    out = out or name

    # Extra layer ensures that src is configurable.
    native.alias(
        name = name + "_actual_executable",
        actual = src,
        visibility = ["//visibility:private"],
        **kwargs
    )
    _write_source_file(
        name = name + "_source.cpp",
        template = Label("executable_dispatcher.template.cpp"),
        actual_executable = name + "_actual_executable",
        out = out,
        append_args = append_args,
        reversed_env = reversed_env,
        source_name = internal_dispatcher_source_name,
        visibility = ["//visibility:private"],
        **kwargs
    )
    cc_binary(
        name = out,
        srcs = [name + "_source.cpp"],
        data = data + [
            name + "_actual_executable",
        ],
        visibility = ["//visibility:private"] if name != out else visibility,
        **kwargs
    )
    if name != out:
        native.alias(
            name = name,
            actual = out,
            visibility = visibility,
            **kwargs
        )

executable_dispatcher = macro(
    doc = "RBE-friendly native_binary() that supports embedding args and env.",
    implementation = _executable_dispatcher_impl,
    attrs = {
        "src": attr.label(
            doc = "The actual executable.",
            cfg = "target",
            allow_files = True,
            mandatory = True,
        ),
        "out": attr.string(
            doc = """Default is name.
                Unlike skylib's native_binary(), this rule doesn't add `.exe`.
            """,
            configurable = False,
        ),
        "data": attr.label_list(allow_files = True),
        "append_args": attr.string_list(
            doc = """Extra arguments that are appended at the end.

                For example, if you have

                ```
                executable_dispatcher(name = "foo", append_args = ["--preset"]),
                ```

                then, the following are functionally equivalent:

                ```shell
                bazel run -- //:foo --runtime-arg

                foo --runtime-arg --preset
                ```
            """,
        ),
        "reversed_env": attr.label_keyed_string_dict(
            doc = """
                Extra environment variables.

                Keys: Labels with exactly one file. Their file path becomes the
                **value** of the environment variable.
                Note: files of these targets are not automatically added to
                runfiles (data). For directories mentioned in keys, add the
                directory content (files in the directory and subdirectories)
                to `data`. For files mentioned in keys, add the file to `data`
                directly.

                Values: Name (**key**) of the environment variable.
            """,
            allow_files = True,
        ),
        "internal_dispatcher_source_name": attr.string(
            doc = "If set, use the given name as the .cpp source file name.",
        ),
    },
)
