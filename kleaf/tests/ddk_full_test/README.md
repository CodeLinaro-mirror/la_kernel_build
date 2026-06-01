# DDK Full Integration / E2E Tests

This package contains full integration and end-to-end (E2E) tests for Kleaf DDK.
These tests compile real modules using the GKI kernel build
(`//common:kernel_aarch64`) and verify the correctness of the generated outputs.

These tests are structurally similar to `ddk_examples`, but they are not
intended as copy-pasteable examples for users to follow. They exist to test edge
cases, bug fixes, and internal DDK details.

## Running Tests

These tests are slow as they require a real kernel build. They are included in
the test suite for `//common:kernel_aarch64`.

To run them manually:

```shell
tools/bazel test //build/kernel/kleaf/tests/ddk_full_test/...
```
