load("//build/kernel/kleaf/impl:common_providers.bzl", "KernelPlatformToolchainInfo")

def _configure_and_make_impl(ctx):
    configure = ctx.file.configure
    srcs = ctx.files.srcs
    bin = ctx.outputs.bin
    include = ctx.outputs.include
    lib64 = ctx.outputs.lib64

    outputs = []
    outputs.extend(bin)
    outputs.extend(include)
    outputs.extend(lib64)

    # Get toolchain info
    toolchain = ctx.attr._toolchain[KernelPlatformToolchainInfo]
    cflags = """ """.join(ctx.attr.cflags + toolchain.cflags)
    ldflags = """ """.join(ctx.attr.ldflags + toolchain.ldflags)
    configure_options = """ """.join(ctx.attr.configure_options)

    # Setup toolchain environment
    command = """
        set -o errexit
        ROOT_DIR="$PWD"
        export PATH="${{ROOT_DIR}}/{path}:${{PATH}}"
    """.format(
        path = toolchain.bin_path,
    )

    # Pass the required flags to use the toolchain, then configure and make
    command += """
        CFLAGS="{cflags}" \\
        LDFLAGS="{ldflags}" \\
        AR=llvm-ar \\
        RANLIB=llvm-ranlib \\
        WINDRES=llvm-windres \\
        {configure} --prefix=/ linux-x86_64-clang {configure_options}

        make -j$(nproc) -s

        mkdir out
        make -j$(nproc) DESTDIR=out install_sw -s
    """.format(
        cflags = cflags,
        ldflags = ldflags,
        configure = configure.path,
        configure_options = configure_options,
    )

    # Copy the installed files to the corresponding outs
    for header in ctx.outputs.include:
        command += """
            cp out/include/openssl/{filename} {filepath}
        """.format(
            filename = header.basename,
            filepath = header.path,
        )

    for binary in ctx.outputs.bin:
        command += """
            cp out/bin/{filename} {filepath}
        """.format(
            filename = binary.basename,
            filepath = binary.path,
        )

    for library in ctx.outputs.lib64:
        command += """
            cp out/lib64/{filename} {filepath}
        """.format(
            filename = library.basename,
            filepath = library.path,
        )

    ctx.actions.run_shell(
        mnemonic = "OpenSSLBuild",
        inputs = depset(srcs),
        outputs = outputs,
        tools = toolchain.all_files,
        command = command,
        progress_message = "Building {}".format(ctx.label),
    )

configure_and_make = rule(
    implementation = _configure_and_make_impl,
    attrs = {
        "srcs": attr.label_list(allow_files = True),
        "cflags": attr.string_list(),
        "ldflags": attr.string_list(),
        "configure": attr.label(allow_single_file = True),
        "configure_options": attr.string_list(),
        "bin": attr.output_list(),
        "include": attr.output_list(),
        "lib64": attr.output_list(),
        "_toolchain": attr.label(
            doc = """
                Use kernel target platform toolchain which provides collated
                information about the resolved toolchain (the kleaf default
                clang linux x86_64 toolchain).
            """,
            default = "//build/kernel/kleaf/impl:kernel_toolchain_target",
        ),
    },
)
