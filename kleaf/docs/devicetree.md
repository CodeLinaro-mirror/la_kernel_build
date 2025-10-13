# Building devicetree

## Building dtb and dtbo

The ruleset
[rules_devicetree](http://github.com/bazel-contrib/rules_devicetree/) contains
all rules you need to build `*.dtb`, `*.dtbo`, and composite `*.dtb`s.

The ruleset is added as a `bazel_dep()` to the [`@kleaf` module](bzlmod.md).

Toolchains have already been configured according to the
[guidelines](https://github.com/bazel-contrib/rules_devicetree/blob/main/docs/configuring_toolchain.md).

For instructions on using the `dtb()`, `dtbo()` and `composite_dtb()` rules, see
[Building devicetrees](https://github.com/bazel-contrib/rules_devicetree/blob/main/docs/building.md).

API reference for these rules may be found
[here](https://github.com/bazel-contrib/rules_devicetree/tree/main/docs/api).

Examples:

*   [rules_devicetree e2e smoke test](https://github.com/bazel-contrib/rules_devicetree/blob/main/e2e/smoke/BUILD)
*   [Pixel 2021](https://android.googlesource.com/kernel/google-modules/raviole-device/+/refs/heads/android-gs-raviole-mainline/arch/arm64/boot/dts/BUILD.bazel)

### dtcopts

The `dtb()` and `dtbo()` rules accept a `dtcopts` attribute that provides
extra flags to `dtc`. This is similar to `DTC_FLAGS` in build configs which is
deprecated.

For details, see
[documentation on rules_devicetree](https://github.com/bazel-contrib/rules_devicetree/blob/main/docs/building.md).

### Adding DTC_INCLUDE from the kernel source tree

If your need to include `*.dtsi` or `.h` file from the Android kernel source
tree, you may put `//common:dtc_includes_aarch64` (or the corresponding target
for your architecture) in `deps`.

Note that `includes` in `deps` have higher priority. Hence, if you need to
override `*.dtsi` or `.h` files from the Android kernel source tree,
you may define an intermediate `devicetree_library` target to enforce the
priority.

In the example below, the `# do not sort` ensures that `buildifier` does not
re-order the `deps` attribute of `:dtc_includes`. Now, you can use this
`:dtc_includes` target in the `deps` of your various `dtb()` and `dtbo()`
targets.

```python
devicetree_library(
    name = "dtc_includes_override",
    hdrs = ["include/foo.dtsi", "include/dt-bindings/foo.h"],
    includes = [
        "include",
    ],
)

devicetree_library(
    name = "dtc_includes",
    deps = [
        # do not sort
        ":dtc_includes_override",         # High priority
        "//common:dtc_includes_aarch64",  # Low  priority
    ],
)
```

Example for Pixel 2021 (see the `dtc_includes` target):

[https://android.googlesource.com/kernel/google-modules/raviole-device/+/refs/heads/android-gs-raviole-mainline/BUILD.bazel](https://android.googlesource.com/kernel/google-modules/raviole-device/+/refs/heads/android-gs-raviole-mainline/BUILD.bazel)

## Building dtb_image and dtbo_image

Kleaf provides the `dtb_image` and `dtbo_image` rules to build these images so
the devicetrees can be used on an Android device.

To concatenate multiple DT blobs to embed it in a `boot` or `vendor_boot`
partition, use the [`dtb_image`](api_reference/kernel.md#dtb_image) rule. The `dtb_image` rule
**does not build the `dtb` partition image**. Then, you may specify the `dtb_image()` target in the
`vendor_boot(dtb_image=)` attribute. See
[DTB images](https://source.android.com/docs/core/architecture/bootloader/dtb-images)
for details.

To build the `dtb` or `dtbo` partition image with the `dt_table_entry` table header, use the
[`dtbo_image`](api_reference/kernel.md#dtbo_image) rule. See
[DTB and DTBO partitions](https://source.android.com/docs/core/architecture/dto/partitions)
for details.

The `srcs` attributes of the two targets should contain the `*.dtb` and `*.dtbo`
files you declare in the previous step.

Example for Pixel 2021 (see the `slider_dtb` and `slider_dtbo` target):

[https://android.googlesource.com/kernel/google-modules/raviole-device/+/refs/heads/android-gs-raviole-mainline/BUILD.bazel](https://android.googlesource.com/kernel/google-modules/raviole-device/+/refs/heads/android-gs-raviole-mainline/BUILD.bazel)
