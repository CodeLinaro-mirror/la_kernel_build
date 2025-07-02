# The Kernel Address Sanitizer (KASAN)

To build with [KASAN](https://docs.kernel.org/dev-tools/kasan.html) enabled, add
the `--kasan` flag. Example:

```shell
$ tools/bazel build --kasan //common:kernel_aarch64
```

Alternatively, use the `sanitizers` attribute of `kernel_build`:

```python
kernel_build(
    name = "tuna_kasan",
    sanitizers = ["kasan_any_mode"],
    ...
)
```

## See also

[LTO](lto.md)

[Sandboxing](sandbox.md)
