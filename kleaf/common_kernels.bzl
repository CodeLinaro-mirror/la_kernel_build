# Copyright (C) 2021 The Android Open Source Project
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

"""Functions that are useful in the common kernel package (usually `//common`)."""

load("@bazel_skylib//lib:paths.bzl", "paths")
load("@bazel_skylib//rules:write_file.bzl", "write_file")
load("@rules_pkg//pkg:install.bzl", "pkg_install")
load("@rules_pkg//pkg:mappings.bzl", "pkg_files", "strip_prefix")
load("//build/kernel/kleaf/artifact_tests:device_modules_test.bzl", "device_modules_test")
load("//build/kernel/kleaf/artifact_tests:kernel_test.bzl", "initramfs_modules_options_test")
load("//build/kernel/kleaf/impl:abi/kernel_abi_dist.bzl", "kernel_abi_wrapped_dist_internal")
load("//build/kernel/kleaf/impl:gki_artifacts.bzl", "gki_artifacts")
load("//build/kernel/kleaf/impl:image/initramfs.bzl", "initramfs")
load("//build/kernel/kleaf/impl:image/kernel_images.bzl", "kernel_images_filegroup")
load("//build/kernel/kleaf/impl:kernel_filegroup_declaration.bzl", "kernel_filegroup_declaration")
load(
    "//build/kernel/kleaf/impl:kernel_prebuilt_utils.bzl",
    "CI_TARGET_MAPPING",
)
load("//build/kernel/kleaf/impl:kernel_sbom.bzl", "kernel_sbom")
load("//build/kernel/kleaf/impl:out_headers_allowlist_archive.bzl", "out_headers_allowlist_archive")
load("//build/kernel/kleaf/tests/defconfig_test:pre_defconfig_fragments_menuconfig_test.bzl", "pre_defconfig_fragments_menuconfig_test")
load(
    ":kernel.bzl",
    "kernel_abi",
    "kernel_build",
    "kernel_build_output",
    "kernel_modules_install",
    "kernel_unstripped_modules_archive",
    "system_dlkm_image",
)

# Always collect_unstripped_modules for common kernels.
_COLLECT_UNSTRIPPED_MODULES = True

# Always strip modules for common kernels.
_STRIP_MODULES = True

# Always keep a copy of Module.symvers and .config for common kernels.
_KEEP_MODULE_SYMVERS = True
_KEEP_DOT_CONFIG = True

# This transition is not needed for GKI
_GKI_ADD_VMLINUX = False

def common_kernel(
        name,
        outs,
        makefile = None,
        arch = None,
        visibility = None,
        defconfig = None,
        check_defconfig = None,
        pre_defconfig_fragments = None,
        post_defconfig_fragments = None,
        kmi_symbol_list = None,
        additional_kmi_symbol_lists = None,
        trim_nonlisted_kmi = None,
        kmi_symbol_list_strict_mode = None,
        kmi_symbol_list_add_only = None,
        module_implicit_outs = None,
        modules_superset = None,
        protected_module_names_list = None,
        gki_system_dlkm_modules = None,
        make_goals = None,
        abi_definition_stg = None,
        kmi_enforced = None,
        build_gki_artifacts = None,
        gki_boot_img_sizes = None,
        page_size = None,
        deprecation = None,
        ddk_headers_archive = None,
        ddk_module_headers = None,
        extra_dist = None,
        kcflags = None,
        system_dlkm_extra_archive_files = None,
        clang_autofdo_profile = None,
        generated_headers_for_module = None):
    """Macro for an Android Common Kernel.

    The following targets are declared as public API:
    -   `<name>_sources` (e.g. `kernel_aarch64_sources`)
        -   Convenience filegroups that refers to all sources required to
            build `<name>` and related targets.
    -   `<name>` (e.g. `kernel_aarch64`): [`kernel_build()`](kernel.md#kernel_build)
        -   This build the main kernel build artifacts, e.g. `vmlinux`, etc.
    -   `<name>_uapi_headers` (e.g. `kernel_aarch64_uapi_headers`)
        -   build `kernel-uapi-headers.tar.gz`.
    -   `<name>_modules` (e.g. `kernel_aarch64_modules`)
    -   `<name>_additional_artifacts` (e.g. `kernel_aarch64_additional_artifacts`)
        -   contains additional artifacts that may be added to
            a distribution. This includes:
            -   Images, including `system_dlkm`, etc.
            -   `kernel-headers.tar.gz`
    -   `<name>_dist` (e.g. `kernel_aarch64_dist`)
        -   can be run to obtain a distribution outside the workspace.

    **ABI monitoring**
    If `kmi_symbol_list` is set, ABI monitoring is turned on.

    -    `<name>_abi` (e.g. `kernel_aarch64_abi`): [`kernel_abi()`](kernel.md#kernel_abi)
    -    `<name>_abi_dist` (e.g. `kernel_aarch64_abi_dist`)

    Usually, for ABI monitoring to be fully turned on, you should set:
    -   `kmi_symbol_list`
    -   `additional_kmi_symbol_lists`
    -   `trim_nonlisted_kmi` to True
    -   `kmi_symbol_list_strict_mode` to True
    -   `abi_definition_stg` to the ABI definition
    -   `kmi_enforced` to True

    Args:
        name: name of the kernel_build().
        outs: See [kernel_build.outs](kernel.md#kernel_build-outs)
        arch: See [kernel_build.arch](kernel.md#kernel_build-arch)
        makefile: See [kernel_build.makefile](kernel.md#kernel_build-makefile)
        defconfig: See [kernel_build.defconfig](kernel.md#kernel_build-defconfig)
        check_defconfig: Non-configurable. See [kernel_build.check_defconfig](kernel.md#kernel_build-check_defconfig).

            If value is `None`, default value is the following:
            -   If `--gki_build_config_fragment` is set, default is "disabled".
            -   Otherwise:
                -   If `pre_defconfig_fragments` is set, default is "match".
                -   Otherwise, default is "minimized".

        pre_defconfig_fragments: See [kernel_build.pre_defconfig_fragments](kernel.md#kernel_build-pre_defconfig_fragments)
        post_defconfig_fragments: See [kernel_build.post_defconfig_fragments](kernel.md#kernel_build-post_defconfig_fragments)
        kmi_symbol_list: See [kernel_build.kmi_symbol_list](kernel.md#kernel_build-kmi_symbol_list)
        additional_kmi_symbol_lists: See [kernel_build.additional_kmi_symbol_lists](kernel.md#kernel_build-additional_kmi_symbol_lists)
        trim_nonlisted_kmi: See [kernel_build.trim_nonlisted_kmi](kernel.md#kernel_build-trim_nonlisted_kmi)
        kmi_symbol_list_strict_mode: See [kernel_build.kmi_symbol_list_strict_mode](kernel.md#kernel_build-kmi_symbol_list_strict_mode)
        module_implicit_outs: See [kernel_build.module_implicit_outs](kernel.md#kernel_build-module_implicit_outs)
        modules_superset: nonconfigurable. The superset of modules targets to create. This should
            contain all modules in each branch in the select() of module_implicit_outs.

            The first module must not be in any conditional branch.
        kmi_symbol_list_add_only: See [kernel_abi.kmi_symbol_list_add_only](kernel.md#kernel_abi-kmi_symbol_list_add_only)
        protected_module_names_list: See [kernel_config.protected_module_names_list](kernel.md#kernel_config-protected_module_names_list)
        make_goals: See [kernel_build.make_goals](kernel.md#kernel_build-make_goals)
        abi_definition_stg: See [kernel_abi.abi_definition_stg](kernel.md#kernel_abi-abi_definition_stg)
        kmi_enforced: See [kernel_abi.kmi_enforced](kernel.md#kernel_abi-kmi_enforced)
        page_size: See [kernel_build.page_size](kernel.md#kernel_build-page_size)
        ddk_module_headers: See [kernel_build.ddk_module_headers](kernel.md#kernel_build-ddk_module_headers)
        gki_system_dlkm_modules: system_dlkm module_list
        build_gki_artifacts: nonconfigurable. If true, build GKI artifacts under
            target name `<name>_gki_artifacts`.
        gki_boot_img_sizes: gki_artifacts.boot_img_sizes
        visibility: default visibility for some targets instantiated with this macro
        deprecation: If set, mark target deprecated with given message.
        ddk_headers_archive: nonconfigurable. Target to the archive packing DDK headers
        extra_dist: extra targets added to `<name>_dist`
        kcflags: [kernel_build.kcflags](kernel.md#kernel_build-kcflags)
        system_dlkm_extra_archive_files: [system_dlkm_image.internal_extra_archive_files](#system_dlkm_image-internal_extra_archive_files)
        clang_autofdo_profile: See [kernel_build.clang_autofdo_profile](kernel.md#kernel_build-clang_autofdo_profile)
        generated_headers_for_module: See [kernel_build.generated_headers_for_module](kernel.md#kernel_build-generated_headers_for_module)
    """

    native.alias(
        name = name + "_sources",
        actual = ":common_kernel_sources",
    )

    all_kmi_symbol_lists = additional_kmi_symbol_lists
    all_kmi_symbol_lists = [] if all_kmi_symbol_lists == None else list(all_kmi_symbol_lists)

    # Add user KMI symbol lists to additional lists
    additional_kmi_symbol_lists = all_kmi_symbol_lists + [
        "//build/kernel/kleaf:user_kmi_symbol_lists",
    ]

    if kmi_symbol_list:
        all_kmi_symbol_lists.append(kmi_symbol_list)

    native.filegroup(
        name = name + "_all_kmi_symbol_lists",
        srcs = all_kmi_symbol_lists,
    )

    if check_defconfig == None:
        check_defconfig = select({
            Label("//build/kernel/kleaf:gki_build_config_fragment_is_unset"): "match" if pre_defconfig_fragments else "minimized",
            "//conditions:default": "disabled",
        })

    kernel_build(
        name = name,
        srcs = [name + "_sources"],
        outs = outs,
        arch = arch,
        implicit_outs = [
            # Kernel build time module signing utility and keys
            # Only available during GKI builds
            # Device fragments need to add: '# CONFIG_MODULE_SIG_ALL is not set'
            "scripts/sign-file",
            "certs/signing_key.pem",
            "certs/signing_key.x509",
        ],
        build_config = Label("//build/kernel/kleaf:gki_build_config_fragment"),
        makefile = makefile,
        check_defconfig = check_defconfig,
        defconfig = defconfig,
        pre_defconfig_fragments = pre_defconfig_fragments,
        post_defconfig_fragments = post_defconfig_fragments,
        visibility = visibility,
        collect_unstripped_modules = _COLLECT_UNSTRIPPED_MODULES,
        strip_modules = _STRIP_MODULES,
        keep_module_symvers = _KEEP_MODULE_SYMVERS,
        keep_dot_config = _KEEP_DOT_CONFIG,
        kmi_symbol_list = kmi_symbol_list,
        additional_kmi_symbol_lists = additional_kmi_symbol_lists,
        trim_nonlisted_kmi = trim_nonlisted_kmi,
        kmi_symbol_list_strict_mode = kmi_symbol_list_strict_mode,
        module_implicit_outs = module_implicit_outs,
        protected_module_names_list = protected_module_names_list,
        make_goals = make_goals,
        page_size = page_size,
        deprecation = deprecation,
        pack_module_env = True,
        ddk_module_defconfig_fragments = [
            Label("//build/kernel/kleaf/impl/defconfig:signing_modules_disabled"),
        ],
        ddk_module_headers = ddk_module_headers,
        kcflags = kcflags,
        clang_autofdo_profile = clang_autofdo_profile,
        generated_headers_for_module = generated_headers_for_module,
        generate_out_targets = not modules_superset,
    )

    if not modules_superset:
        # buildifier: disable=print
        print("""\
WARNING: common_kernels(modules_superset=) is not set for {}.
    This will not be supported in the future.
""".format(native.package_relative_label(name)))

    # If modules_superset is set, generate_out_targets is False so we need
    # to define module targets ourselves.
    for module_name in modules_superset:
        kernel_build_output(
            name = name + "/" + module_name,
            out = module_name,
            kernel_build = name,
        )

        if paths.basename(module_name) != module_name:
            native.alias(
                name = name + "/" + paths.basename(module_name),
                actual = name + "/" + module_name,
            )

    kernel_abi(
        name = name + "_abi",
        kernel_build = name,
        visibility = visibility,
        define_abi_targets = bool(kmi_symbol_list),
        # Sync with KMI_SYMBOL_LIST_MODULE_GROUPING
        module_grouping = None,
        abi_definition_stg = abi_definition_stg,
        kmi_enforced = kmi_enforced,
        kmi_symbol_list_add_only = kmi_symbol_list_add_only,
        deprecation = deprecation,
        enable_add_vmlinux = _GKI_ADD_VMLINUX,
    )

    # A subset of headers in OUT_DIR that only contains scripts/. This is useful
    # for DDK headers interpolation.
    out_headers_allowlist_archive(
        name = name + "_script_headers",
        kernel_build = name,
        subdirs = ["scripts"],
    )

    native.filegroup(
        name = name + "_ddk_allowlist_headers",
        srcs = [
            name + "_script_headers",
            name + "_uapi_headers",
        ],
        visibility = [
            Label("//build/kernel/kleaf:__pkg__"),
        ],
    )

    kernel_modules_install(
        name = name + "_modules_install",
        # The GKI target does not have external modules. GKI modules goes
        # into the in-tree kernel module list, aka kernel_build.module_implicit_outs.
        # Hence, this is empty.
        kernel_modules = [],
        kernel_build = name,
    )

    kernel_unstripped_modules_archive(
        name = name + "_unstripped_modules_archive",
        kernel_build = name,
    )

    system_dlkm_image(
        name = name + "_system_dlkm_image",
        kernel_modules_install = name + "_modules_install",
        build_flatten = True,
        modules_list = gki_system_dlkm_modules,
        fs_types = ["erofs", "ext4"],
        internal_extra_archive_files = system_dlkm_extra_archive_files,
    )

    kernel_images_filegroup(
        name = name + "_images",
        srcs = [name + "_system_dlkm_image"],
        deprecation = "Use {} instead".format(native.package_relative_label(name + "_system_dlkm_image")),
    )

    if build_gki_artifacts:
        gki_artifacts(
            name = name + "_gki_artifacts",
            kernel_build = name,
            boot_img_sizes = gki_boot_img_sizes,
            arch = arch,
        )
    else:
        native.filegroup(
            name = name + "_gki_artifacts",
            srcs = [],
        )

    # modules_staging_archive from <name>
    native.filegroup(
        name = name + "_modules_staging_archive",
        srcs = [name],
        output_group = "modules_staging_archive",
    )

    # All GKI modules
    native.filegroup(
        name = name + "_modules",
        srcs = [
            "{}/{}".format(name, module)
            for module in (modules_superset or [])
        ],
    )

    # The purpose of this target is to allow device kernel build to include reasonable
    # defaults of artifacts from GKI. Hence, this target includes everything in name + "_dist",
    # excluding the following:
    # - UAPI headers, because device-specific external kernel modules may install different
    #   headers.
    # - DDK; see _ddk_artifacts below.
    native.filegroup(
        name = name + "_additional_artifacts",
        srcs = [
            # Sync with additional_artifacts_items
            name + "_headers",
            name + "_system_dlkm_image",
            name + "_kmi_symbol_list",
            name + "_raw_kmi_symbol_list",
            name + "_gki_artifacts",
        ],
    )

    filegroup_extra_deps = [
        name + "_unstripped_modules_archive",
    ]
    kernel_filegroup_declaration(
        name = name + "_filegroup_declaration",
        kernel_build = name,
        extra_deps = filegroup_extra_deps,
        images = name + "_system_dlkm_image",
        ddk_module_headers = ddk_module_headers,
        visibility = ["//visibility:private"],
    )
    target_mapping = CI_TARGET_MAPPING.get(name, {})
    write_file(
        name = name + "_ci_target_mapping",
        content = [
            json.encode_indent(target_mapping),
        ],
        # / is needed to distinguish between variants as 16k (and avoid conflicts).
        out = name + "/ci_target_mapping.json",
    )

    # Everything in name + "_dist" for the DDK.
    # These are necessary for driver development. Hence they are also added to
    # kernel_*_dist so they can be downloaded.
    ddk_artifacts = [
        name + "_ci_target_mapping",
        name + "_filegroup_declaration",
        name + "_unstripped_modules_archive",
    ]
    if ddk_headers_archive:
        ddk_artifacts.append(ddk_headers_archive)
    native.filegroup(
        name = name + "_ddk_artifacts",
        srcs = ddk_artifacts,
    )

    dist_targets = (extra_dist or []) + [
        name,
        name + "_uapi_headers",
        name + "_additional_artifacts",
        name + "_ddk_artifacts",
        name + "_modules",
        name + "_modules_install",
        # BUILD_GKI_CERTIFICATION_TOOLS=1 for all kernel_build defined here.
        Label("//build/kernel:gki_certification_tools"),
        "build.config.constants",
        Label("//build/kernel:init_ddk_zip"),
    ]

    kernel_sbom(
        name = name + "_sbom",
        srcs = dist_targets,
        kernel_build = name,
    )

    dist_targets.append(name + "_sbom")

    pkg_files(
        name = name + "_dist_files",
        srcs = dist_targets,
        strip_prefix = strip_prefix.files_only(),
        visibility = ["//visibility:private"],
    )
    pkg_install(
        name = name + "_dist",
        srcs = [name + "_dist_files"],
        destdir = "out/{name}/dist".format(name = name),
    )

    kernel_abi_dist_name = name + "_abi_dist"
    _common_kernel_abi_dist(
        name = kernel_abi_dist_name,
        kernel_abi = name + "_abi",
        dist_targets = dist_targets,
    )

    _common_kernel_abi_dist(
        name = name + "_abi_ignore_diff_dist",
        kernel_abi = name + "_abi",
        dist_targets = dist_targets,
        ignore_diff = True,
        no_ignore_diff_target = kernel_abi_dist_name,
    )

    _define_common_kernels_additional_tests(
        name = name + "_additional_tests",
        kernel_build_name = name,
        kernel_modules_install = name + "_modules_install",
        modules = (modules_superset or []),
        arch = arch,
        page_size = page_size,
        makefile = makefile,
        defconfig = defconfig,
        pre_defconfig_fragments = pre_defconfig_fragments,
    )

    native.test_suite(
        name = name + "_tests",
        tests = [
            name + "_additional_tests",
            name + "_test",
            name + "_modules_test",
        ],
    )

def _define_common_kernels_additional_tests(
        name,
        kernel_build_name,
        makefile,
        defconfig,
        kernel_modules_install,
        modules,
        arch,
        page_size,
        pre_defconfig_fragments):
    fake_modules_options = Label("//build/kernel/kleaf/artifact_tests:fake_modules_options.txt")

    initramfs(
        name = name + "_fake_initramfs",
        kernel_modules_install = kernel_modules_install,
        modules_options = fake_modules_options,
    )

    initramfs_modules_options_test(
        name = name + "_fake",
        kernel_images = name + "_fake_initramfs",
        expected_modules_options = fake_modules_options,
    )

    write_file(
        name = name + "_empty_modules_options",
        out = name + "_empty_modules_options/modules.options",
        content = [],
    )

    initramfs(
        name = name + "_empty_initramfs",
        kernel_modules_install = kernel_modules_install,
        # Not specify module_options
    )

    initramfs_modules_options_test(
        name = name + "_empty",
        kernel_images = name + "_empty_initramfs",
        expected_modules_options = name + "_empty_modules_options",
    )

    device_modules_test(
        name = name + "_device_modules_test",
        srcs = [kernel_build_name + "_sources"],
        base_kernel_label = native.package_relative_label(kernel_build_name),
        base_kernel_module = min(modules) if modules else None,
        arch = arch,
        page_size = page_size,
    )

    kernel_build(
        name = name + "_test_device_kernel",
        arch = arch,
        page_size = page_size,
        makefile = makefile,
        defconfig = defconfig,
        pre_defconfig_fragments = [Label("//build/kernel/kleaf/tests/defconfig_test:pre_defconfig_fragment")],
        base_kernel = native.package_relative_label(kernel_build_name),
        make_goals = ["modules"],
        # We don't actually build the kernel_build target, so we don't care about outputs
        outs = [],
        testonly = True,
        tags = ["manual"],
        visibility = ["//visibility:private"],
    )

    extra_tests = []

    # Omit this test for base kernels with pre_defconfig_fragments set (e.g. TV).
    if not pre_defconfig_fragments:
        # Tests that, if the menuconfig command does not edit anything, the pre_defconfig_fragment
        # should still stay the same.
        pre_defconfig_fragments_menuconfig_test(
            name = name + "_pre_defconfig_fragments_menuconfig_test",
            kernel_build = name + "_test_device_kernel",
            pre_defconfig_fragment = Label("//build/kernel/kleaf/tests/defconfig_test:pre_defconfig_fragment"),
            visibility = ["//visibility:private"],
        )
        extra_tests.append(name + "_pre_defconfig_fragments_menuconfig_test")

    # Build ddk_examples to make sure our DDK examples are up-to-date. Note that these examples
    # deliberately refers to //common explicitly to provide a clear example, so this build test
    # is only included when we are building //common:kernel_aarch64.
    if native.package_relative_label(kernel_build_name) == native.package_relative_label("//common:kernel_aarch64"):
        extra_tests += [
            Label("//build/kernel/kleaf/tests/built_with_ddk_test"),
            Label("//build/kernel/kleaf/tests/ddk_examples"),
            Label("//build/kernel/kleaf/tests/ddk_test:ddk_images_test_suite"),
            Label("//build/kernel/kleaf/tests/merge_module_symvers_test"),
        ]

        # Building pKVM module with DDK is only supported if the following file exists.
        if native.glob(["arch/arm64/kvm/hyp/nvhe/Makefile.module"], allow_empty = True):
            extra_tests.append(
                Label("//build/kernel/kleaf/tests/ddk_examples:pkvm_module_test"),
            )

    native.test_suite(
        name = name,
        tests = [
            name + "_empty",
            name + "_fake",
            name + "_device_modules_test",
        ] + extra_tests,
    )

def _common_kernel_abi_dist(
        name,
        kernel_abi,
        dist_targets,
        ignore_diff = None,
        no_ignore_diff_target = None):
    """Defines a `kernel_abi_wrapped_dist` for a common kernel."""

    pkg_files(
        name = name + "_internal_files",
        srcs = dist_targets + [kernel_abi],
        strip_prefix = strip_prefix.files_only(),
        visibility = ["//visibility:private"],
    )

    pkg_install(
        name = name + "_internal",
        srcs = [name + "_internal_files"],
        destdir = "out_abi/{name}/dist".format(name = name),
    )

    # TODO(b/231647455): Clean up hard-coded name "_abi_diff_executable".
    kernel_abi_wrapped_dist_internal(
        name = name,
        dist = name + "_internal",
        diff_stg = kernel_abi + "_diff_executable",
        enable_add_vmlinux = _GKI_ADD_VMLINUX,
        ignore_diff = ignore_diff,
        no_ignore_diff_target = no_ignore_diff_target,
    )
