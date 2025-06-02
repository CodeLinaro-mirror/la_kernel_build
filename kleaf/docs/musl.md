# Use musl libc for host binaries

The musl libc is used for most host binaries, replacing glibc. This includes,
but not limited to:

- Prebuilt tools in `prebuilts/build-tools` and `prebuilts/kernel-build-tools`
- All `cc_binary()`s, including hermetic tools built from sources
- Kbuild, when building host programs like fixdep, objtool, kconfig, etc.
- The Python interpreter.

Using glibc in Kleaf for host binaries is no longer supported, with a few
[exceptions](#exceptions).

## Resolving errors in `cc_binary`

The `linux_musl-x86_64` clang toolchain does the following:

- If a `cc_binary` has `linkstatic = True` (the default), it also enables the
  `fully_static_link` feature, which adds `-static` to linkopts.
- If a `cc_binary` has `linkstatic = False`, it automatically adds
  `libc_musl.so` to library search paths (`-L`) and runtime library search paths
  (`-rpath`).

Because of this, your `cc_binary` building against the execution platform may
encounter errors. If you get errors about missing libraries like the following:

```
ld.lld: error: unable to find library -lbase
```

It is likely because your binary used to have `linkstatic = True` (the default),
which preferred using static libraries but was still permitted to link to
dynamic libraries. In the first case, without `--config=host_platform`, the
binary preferred using `libbase.a` (which might not exist) but were still
allowed to link to `libbase.so`. However, with `--config=host_platform`,
`linkstatic = True` implies `-static`, causing `libbase.so` to be dropped from
linkopts.

If you get error about missing `libgcc_s.so` like:

```
Error loading shared library libgcc_s.so.1: No such file or directory (needed by <omitted>/libbase.so)
```

It is likely because you are building against libraries that was prebuilt
against glibc.

The solutions of these errors involve doing one or more of following:

- Check that your `cc_binary` has `linkstatic = False`. This will link
  dependencies dynamically, resolving errors like the first one when the
  dependency (`libbase`) only provides the shared variant.
- If the failure is on a custom library (`cc_library` or `cc_import`), ensure it
  provides the static and/or shared variant depending on the value of
  `linkstatic` in the `cc_binary`.
- If the failure is on a custom prebuilt library (`cc_import`), ensure that
  the prebuilt library links against musl libc. In the second error above,
  switching from `//prebuilts/kernel-build-tools:linux_x86_imported_libs`
  to `//prebuilts/kernel-build-tools:imported_libs` resolves the error.

See `//build/kernel/kleaf/tests/cc_testing` for a list of supported use cases.

## Exceptions

As of 2025-06-02, during a regular kernel build process, the following still
relies on glibc:

- The prebuilt Bazel binary.
- All tools from the host. See [Known violations in hermeticity](hermeticity.md#known-violations).
- The Rust toolchain itself relies on host glibc.
  - As a result, Rust `proc_macros` relies on checked-in glibc headers in `prebuilts/gcc`.

## See also

[Platforms](https://bazel.build/extending/platforms)

[C++ Toolchain Configuration](https://bazel.build/docs/cc-toolchain-config-reference)
