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
load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load("@bazel_skylib//rules:native_binary.bzl", "native_binary")
load("@rules_cc//cc:cc_binary.bzl", "cc_binary")
load(":native_binary_aspect.bzl", "NativeBinaryAspectInfo", "native_binary_aspect")
load(":utils.bzl", "utils")

visibility("//build/kernel/...")

def _get_single_executable(ctx, target):
    # If --nohermetic_tools_symlink_source is set, and src is native_binary, handle a special case:
    # don't use the executable provided by the native_binary() target (which is a symlink), but use
    # the actual source file.
    # This is a hack and it wouldn't work if we had custom rules that uses
    # ctx.action.symlink(), but it is good enough for tools in //prebuilts/build-tools.
    if not ctx.attr._use_symlinks[BuildSettingInfo].value and NativeBinaryAspectInfo in target:
        return target[NativeBinaryAspectInfo].executable

    if target[DefaultInfo].files_to_run.executable:
        return target[DefaultInfo].files_to_run.executable

    # Hack for python_runtime_files() / reversed_env directories
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
    out = ctx.actions.declare_file(ctx.label.name)
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
        file = _get_single_executable(ctx, target)
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
            aspects = [native_binary_aspect],
        ),
        "append_args": attr.string_list(),
        "reversed_env": attr.label_keyed_string_dict(
            allow_files = True,
            aspects = [native_binary_aspect],
        ),
        "out": attr.string(),
        "_use_symlinks": attr.label(
            default = "//build/kernel/kleaf:hermetic_tools_use_symlinks",
        ),
    },
)

def _get_binary_runfiles(ctx, target):
    # If --nohermetic_tools_symlink_source is set, and target is native_binary, handle a special case:
    #   just return native_binary.src + native_binary.data as the runfiles of the
    #   executable_dispatcher.
    # Otherwise just use the runfiles from the target.
    if not ctx.attr._use_symlinks[BuildSettingInfo].value and NativeBinaryAspectInfo in target:
        return depset(
            [target[NativeBinaryAspectInfo].executable],
            transitive = [target[NativeBinaryAspectInfo].runfiles],
        )
    transitive_runfiles = [target.files]
    if target.default_runfiles:
        transitive_runfiles.append(target.default_runfiles.files)

    return depset(transitive = transitive_runfiles)

def _runfiles_helper_impl(ctx):
    data_runfiles = depset(transitive =
                               [target.files for target in ctx.attr.data] +
                               [_get_binary_runfiles(ctx, target) for target in ctx.attr.data])

    executable_runfiles = _get_binary_runfiles(ctx, ctx.attr.actual_executable)

    return DefaultInfo(files = depset(transitive = [data_runfiles, executable_runfiles]))

_runfiles_helper = rule(
    doc = """Helper to calculate runfiles for executable_dispatcher.""",
    implementation = _runfiles_helper_impl,
    attrs = {
        "actual_executable": attr.label(
            allow_files = True,
            aspects = [native_binary_aspect],
        ),
        "data": attr.label_list(
            allow_files = True,
            aspects = [native_binary_aspect],
        ),
        "_use_symlinks": attr.label(
            default = "//build/kernel/kleaf:hermetic_tools_use_symlinks",
        ),
    },
)

def _executable_dispatcher_internal_impl(
        name,
        visibility,
        src,
        data,
        append_args,
        reversed_env,
        **kwargs):
    _write_source_file(
        name = name + "_source.cpp",
        template = Label("executable_dispatcher.template.cpp"),
        actual_executable = src,
        out = name,
        append_args = append_args,
        reversed_env = reversed_env,
        visibility = ["//visibility:private"],
        **kwargs
    )
    _runfiles_helper(
        name = name + "_runfiles_helper",
        actual_executable = src,
        data = data,
        visibility = ["//visibility:private"],
        **kwargs
    )
    cc_binary(
        name = name,
        srcs = [name + "_source.cpp"],
        data = [name + "_runfiles_helper"],
        visibility = visibility,
        **kwargs
    )

executable_dispatcher_internal = macro(
    doc = "RBE-friendly native_binary() that supports embedding args and env.",
    implementation = _executable_dispatcher_internal_impl,
    attrs = {
        "src": attr.label(
            doc = """The actual executable.

                Note: Unless `python_hack` is set, this assumes that `src`' label name's basename is
                the same as name of the actual binary.
            """,
            cfg = "target",
            allow_files = True,
            mandatory = True,
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
    },
)

def executable_dispatcher(
        name,
        src,
        data = None,
        append_args = None,
        reversed_env = None,
        python_hack = None,
        **kwargs):
    """RBE-friendly native_binary() that supports embedding args and env.

    Args:
        name: Name of the target.
        src: [Nonconfigurable](https://bazel.build/reference/be/common-definitions#configurable-attributes).
            The actual executable.

            Note: Unless `python_hack` is set, this assumes that `src`' label name's basename is the
            same as name of the actual binary.
        data: [Nonconfigurable](https://bazel.build/reference/be/common-definitions#configurable-attributes).
            Runfiles.
        append_args: [Nonconfigurable](https://bazel.build/reference/be/common-definitions#configurable-attributes).
            Extra arguments that are appended at the end.
        reversed_env: [Nonconfigurable](https://bazel.build/reference/be/common-definitions#configurable-attributes).
            Extra environment variables.
        python_hack: Enable hack for python.

            `python_runtime_files` can't be used in `native_binary`. This is a hack to avoid
            falling to that case.
        **kwargs: Additional attributes to the internal rule, e.g.
          [`visibility`](https://docs.bazel.build/versions/main/visibility.html).
          See complete list
          [here](https://docs.bazel.build/versions/main/be/common-definitions.html#common-attributes).
    """

    # This is not a symbolic macro because symbolic macros does not allow us
    # to create targets like `_dispatched/<name>`; all targets must start with name.

    simple_target = None
    if not append_args and not reversed_env:
        # If no extra args or env, an alias or native_binary would suffice.
        simple_target = name + "_simple"
        if python_hack or (not data and name == paths.basename(native.package_relative_label(src).name)):
            # Simple case: use alias
            native.alias(
                name = simple_target,
                actual = src,
                **kwargs
            )
        else:
            # Simple case: use native_binary
            native_binary(
                name = simple_target,
                src = src,
                data = data,
                out = name,
                **kwargs
            )

    private_kwargs = kwargs | {
        "visibility": ["//visibility:private"],
    }

    executable_dispatcher_internal(
        name = "_dispatched/" + name,
        src = src,
        data = data,
        append_args = append_args,
        reversed_env = reversed_env,
        **private_kwargs
    )

    native.alias(
        name = name,
        actual = select({
            "//build/kernel/kleaf:hermetic_tools_use_symlinks_is_true": simple_target or "_dispatched/" + name,
            "//conditions:default": "_dispatched/" + name,
        }),
        **kwargs
    )
