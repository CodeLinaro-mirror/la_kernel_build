# deps attribute of ddk_config

This example illustrates how `ddk_config(deps=)` should be set to, especially
for modules with dependencies that has `config`/`defconfig`/`kconfig` set.

Because these dependencies have `config`/`defconfig`/`kconfig` set, they need
to be specified in `ddk_config(deps=)`.

Here's the module dependency graph, roughly:

```
child1 -------> parent1
      \
       >------> parent_without_config
      /
child2 -------> parent2
```

## Explanation

`child1` and `child2` uses a common `ddk_config` target called `child_config`.
Hence, in `child_config`, we need to specify `deps` to be the superset of
all deps of `child1` and `child2` that have config/kconfig/defconfig, which is
`parent1` and `parent2`.

As illustrated in this example, `parent_without_config` may be excluded because
it doesn't have config/kconfig/defconfig. However, in practice, it is still
recommended to include it so that when `parent_without_config` adds
config/kconfig/defconfig, or add deps with them, `child1` and `child2` won't
immediately breaks.

See [children/BUILD.bazel](children/BUILD.bazel) for details.

## Full sources

Full sources of this example are in [this directory](.).
