# Build your kernels and drivers with Bazel

[TOC]

**Note**:
You may view the documentation for the following Bazel rules and macros on
Android Continuous Integration. See
[API Reference and Documentation for all rules](api_reference.md).

## Setting up the workspace

* (Recommended) To use Kleaf tooling as a dependent Bazel module, see
  [Setting up DDK workspace](ddk/workspace.md).
* To use Kleaf tooling as the root Bazel module, see
  [Use @kleaf as root module (legacy)](bzlmod.md#use-kleaf-as-root-module-legacy).
* Building without Bzlmod is deprecated and will not be supported in
  Android 16 and above.

## Building a custom kernel

**WARNING**: It is recommended to use the common Android kernel
under `//common` (the so-called "mixed build") instead of building a custom
kernel.

You may define a `kernel_build` target to build a custom kernel. The name of
the `kernel_build` target is usually the name of your device, e.g. `tuna`.

The `outs` attribute of the target should align with the `FILES` variable in
build.config. This may include DTB files and kernel images, e.g. `vmlinux`.

The `module_outs` attribute of the target includes the list of in-tree drivers
that you are building. See section to [build in-tree drivers (Step 1)](#step-1)
below.

```
load("//build/kernel/kleaf:kernel.bzl","kernel_build")
load("//build/kernel/kleaf:common_kernels.bzl", "arm64_outs")
kernel_build(
   name = "tuna",
   srcs = glob(
       ["**"],
       exclude = [
           "**/BUILD.bazel",
           "**/*.bzl",
           ".git/**",
       ],
   ),
   outs = arm64_outs,
   build_config = "build.config.tuna",
)
```

## Building kernel modules

### Step 1: (Optional) Define a target to build in-tree drivers {#step-1}

If you have a separate kernel tree to build in-tree drivers, define
a `kernel_build` target to build these modules. The name of the `kernel_build`
target is usually the name of your device, e.g. `tuna`.

If you also have external kernel modules to be built, be sure to set visibility
accordingly, so that the targets to build external kernel modules can refer to
this `kernel_build` target.

If you are building a custom kernel, you may reuse the existing `kernel_build`
target, and keep kernel images in `outs`. If you are building against GKI, set
the `base_kernel` attribute accordingly (e.g. to `//common:kernel_aarch64`).

The `makefile` attribute should point to the `Makefile` under the kernel source
tree. Usually, this is `//common:Makefile`.

The `make_goals` attribute should be the list of GNUMake goals you are building.
Usually, this contains `["modules"]`.

The `outs` attribute of the target should align with the `FILES` variable in
build.config. This is sometimes an empty list.

The `module_outs` attribute of the target includes the list of in-tree drivers
that you are building.

* Hint: You may leave the list empty and build the target. If the list is not
  up to date, modify the list according to the error message.

**Note**: It is recommended that kernel modules are moved out of the kernel tree
to be built as external kernel modules. This means keeping the list
of `module_outs` empty or as short as possible. See Step 2 for building external
kernel modules.

For other build configurations defined in the `build.config` file, see
[build_configs.md](build_configs.md).

Example for Pixel 2021 (see the `kernel_build` target named `slider`):

[https://android.googlesource.com/kernel/google-modules/raviole-device/+/refs/heads/android-gs-raviole-mainline/BUILD.bazel](https://android.googlesource.com/kernel/google-modules/raviole-device/+/refs/heads/android-gs-raviole-mainline/BUILD.bazel)

### Step 2: Define targets to build external kernel modules

See [ddk/main.md](ddk/main.md) for details.

### Step 3: Define a target to run `depmod`

Define a `kernel_modules_install` target that includes all external kernel
modules created in Step 2. This is equivalent to running `make modules_install`,
which runs `depmod`.

The name of the target is usually the name of your device
with `_modules_install` appended to it, e.g. `tuna_modules_install`.

See Step 2 to determine the `kernel_build` attribute of the target.

Example for Pixel 2021 (see the `kernel_modules_install` target
named `slider_modules_install`):

[https://android.googlesource.com/kernel/google-modules/raviole-device/+/refs/heads/android-gs-raviole-mainline/BUILD.bazel](https://android.googlesource.com/kernel/google-modules/raviole-device/+/refs/heads/android-gs-raviole-mainline/BUILD.bazel)

### Step 4: (Optional) Define targets for boot images

Define `initramfs`, `vendor_boot_image`, `vendor_dlkm_image`,
`system_dlkm_image` etc.

The name of the target is usually the name of your device with the type
of the image appended to it, e.g. `tuna_initramfs`.

If you do not need to build any partition images, skip this step.

Example for Pixel 2021 (see `slider_initramfs` and `slider_vendor_dlkm_image`):

[https://android.googlesource.com/kernel/google-modules/raviole-device/+/refs/heads/android-gs-raviole-mainline/BUILD.bazel](https://android.googlesource.com/kernel/google-modules/raviole-device/+/refs/heads/android-gs-raviole-mainline/BUILD.bazel)

### Step 5: Define targets for distribution {#step-5}

Define a `pkg_files` target and a `pkg_install` target that includes the targets
you want in the distribution directory. The name of this `pkg_install` target
is usually the name of your device with `_dist` appended to it, e.g.
`tuna_dist`.

You may set `strip_prefix = strip_prefix.files_only()` so the directory
structure within `destdir` is flattened. If an alternative directory structure
is desired, use other rules and functions in `@rules_pkg//pkg:mappings.bzl`
to achieve this.

It is recommended to set `destdir` so you do not have to specify it in the
command line every time.

Add the following to the `srcs` attribute of the `pkg_files` target:

* The name of the `kernel_build` you have created in Step 1,
  e.g. `:tuna`. This adds all `outs`
  and `module_outs` to the distribution directory.
  * This usually includes DTB files and in-tree kernel modules.
* The name of the `kernel_modules_install` target you have created in Step 3.
  You may skip the `ddk_modules` targets created in Step 2, because
  the `kernel_modules_install` target includes all `ddk_modules` targets.
  This copies all external kernel modules to the distribution directory.
* The name of all image targets you have created in Step 4. This copies
  all partition images to the distribution directory.
* GKI artifacts, including:
  * `//common:kernel_aarch64`
  * `//common:kernel_aarch64_additional_artifacts`
* UAPI headers, e.g. `//common:kernel_aarch64_uapi_headers`
* GKI modules
  * If you are using all GKI modules, add `//common:kernel_aarch64_modules`.
  * If you are using part of the GKI modules, add them individually, e.g.:
    * `//common:kernel_aarch64/zram.ko`
    * `//common:kernel_aarch64/zsmalloc.ko`
  * Modules from the device kernel build with the same name as GKI modules
    (e.g. on android13-5.15, you have `zram.ko` in `kernel_build.module_outs`)
    does not need to be specified, because `module_outs` are added to
    distribution.

Then, add the `pkg_files` target to the `srcs` attribute of the `pkg_install`
target.

Example:

```
load("@rules_pkg//pkg:install.bzl", "pkg_install")
load("@rules_pkg//pkg:mappings.bzl", "pkg_files", "strip_prefix")

pkg_files(
    name = "tuna_files",
    srcs = [
        ":tuna",
        ":tuna_images",
        ":tuna_modules_install",
        "//common:kernel_aarch64_uapi_headers",
        "//common:kernel_aarch64",
        "//common:kernel_aarch64_modules",
        "//common:kernel_aarch64_additional_artifacts",
    ],
    strip_prefix = strip_prefix.files_only(),
    visibility = ["//visibility:private"],
)

pkg_install(
    name = "tuna_dist",
    srcs = [":tuna_files"],
    destdir = "out/tuna/dist",
    visibility = ["//visibility:private"],
)
```

See [rules_pkg](https://github.com/bazelbuild/rules_pkg) for details on how to
use `pkg_files`, `strip_prefix`, and `pkg_install` properly.

### Step 6: Build, flash and test

```shell
# Optional: prepare the device by flashing a base build.
# During development, you may want to wipe, disable verity and disable verification.
# fastboot update tuna-img.zip -w --disable-verity --disable-verification

# Assuming dist_dir=out/dist
$ tools/bazel run //private/path/to/sources:tuna_dist
# Flash static partitions
$ fastboot flash boot out/dist/boot.img
$ fastboot flash system_dlkm out/dist/system_dlkm.img
$ fastboot flash vendor_boot out/dist/vendor_boot.img
$ fastboot flash dtbo out/dist/dtbo.img
$ fastboot reboot fastboot
# Flash dynamic partitions
$ fastboot flash vendor_dlkm out/dist/vendor_dlkm.img
$ fastboot reboot
```

## Resolving common errors

See [errors.md](errors.md).

## Handling SCM version

See [scmversion.md](scmversion.md).

## Advanced usage

### Disable LTO during development

LTO is already disabled by default in `gki_defconfig` since 5.19.

### Using configurable build attributes `select()`

See official Bazel documentation for `select()`
here: https://docs.bazel.build/versions/main/configurable-attributes.html

In general, inputs to a target are configurable, while declared outputs are not.
One exception is that the `kernel_build` rule provides limited support
of `select()` in `outs` and `module_outs` attributes. See
[documentations](api_reference.md) of `kernel_build` for details.

### .bazelrc files

By default, the `.bazelrc` (symlink to `build/kernel/kleaf/common.bazelrc`)
tries to import the following two files if they exist:

* `device.bazelrc`: Device-specific bazelrc file (e.g. GKI prebuilt settings)
* `user.bazelrc`: User-specific bazelrc file (e.g. LTO settings)

To add device-specific configurations, you may create a `device.bazelrc`
file in the device kernel tree, then create a symlink at the repo root.

### Notes on hermeticity

Bazel builds are hermetic by default. Hermeticity is ensured by manually
declaring each target to depend on `//build/kernel:hermetic-tools`.

At this time of writing (2025-01-03), the following binaries are still
expected from the environement, or host machine, to build the kernel with
Bazel, in addition to the list of the allowlist of host tools specified in
`//build/kernel:hermetic-tools`. This is because the following usage does
not depend on `//build/kernel:hermetic-tools`.
* `echo`, `readlink`, `git` used by `build/kernel/kleaf/workspace_status.sh`

If you use the following rules, there are known issues of non-hermeticity:

* [`copy_file`](https://github.com/bazelbuild/bazel-skylib/blob/main/rules/copy_file.bzl)
  uses `cp` from the host machine
