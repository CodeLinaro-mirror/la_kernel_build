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

## Building dtb_image and dtbo_image

Kleaf provides the `dtb_image` and `dtbo_image` rules to build these images so
the devicetrees can be used on an Android device.

The `srcs` attributes of the two targets should contain the `*.dtb` and `*.dtbo`
files you declare in the previous step.

Example for Pixel 2021 (see the `slider_dtb` and `slider_dtbo` target):

[https://android.googlesource.com/kernel/google-modules/raviole-device/+/refs/heads/android-gs-raviole-mainline/BUILD.bazel](https://android.googlesource.com/kernel/google-modules/raviole-device/+/refs/heads/android-gs-raviole-mainline/BUILD.bazel)
