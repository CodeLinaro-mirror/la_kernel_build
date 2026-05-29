# DDK Library with All Sources in Library

**Note**: `ddk_library` is experimental. Its API is subject to change.

This example demonstrates how to build a `ddk_module` with no direct source
files, where all source files are compiled within `ddk_library` targets.

It serves as a test case to ensure that `MODULE_LICENSE` and other modinfo tags
are correctly preserved and linked into the final `.ko` module even when there
are no direct sources in the `ddk_module`.

## Explanation

See [BUILD.bazel](BUILD.bazel) for the example.

`mymod` has `srcs = []` and depends on `:libfoo` which contains `mod.c` (the
source file with `MODULE_LICENSE`).

Run the following to build it:

```shell
tools/bazel build \
    //build/kernel/kleaf/tests/ddk_examples/ddk_library_all_srcs:mymod
```

## Full sources

Full sources of this example are in [this directory](.).
