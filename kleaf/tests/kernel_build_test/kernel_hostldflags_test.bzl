# Copyright (C) 2026 The Android Open Source Project
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

"""Tests HOSTLDFLAGS response file generation and Make expansion invariance."""

load("@bazel_skylib//rules:build_test.bzl", "build_test")
load("//build/kernel/kleaf:hermetic_tools.bzl", "hermetic_toolchain")
load("//build/kernel/kleaf/impl:common_providers.bzl", "KernelEnvToolchainsInfo")

def _verify_hostldflags_impl(ctx):
    hermetic_tools = hermetic_toolchain.get(ctx)
    toolchains = ctx.attr._toolchains[KernelEnvToolchainsInfo]
    out = ctx.actions.declare_file("{}/verified.txt".format(ctx.attr.name))

    command = """
        set -e
        set -o pipefail
        {hermetic_setup}

        export ROOT_DIR="${{PWD}}"
        export COMMON_OUT_DIR="${{PWD}}/out/test_hostldflags"
        export OUT_DIR="${{COMMON_OUT_DIR}}/common"

        {toolchains_setup}

        # 1. HOSTLDFLAGS must not contain '$' (avoids Make/shell escaping bugs
        #    such as tools/objtool/Makefile expanding $(HOSTLDFLAGS) once).
        if [[ "${{HOSTLDFLAGS}}" == *'$'* ]]; then
            echo "ERROR: HOSTLDFLAGS contains '$': ${{HOSTLDFLAGS}}" >&2
            exit 1
        fi

        # 2. Extract and verify the linker response file in COMMON_OUT_DIR.
        rsp_files=()
        for tok in ${{HOSTLDFLAGS}}; do
            if [[ "${{tok}}" == -Wl,@* ]]; then
                rsp_files+=("${{tok#-Wl,@}}")
            fi
        done
        if [[ "${{#rsp_files[@]}}" -ne 1 ]]; then
            echo "ERROR: Expected 1 -Wl,@ response file in HOSTLDFLAGS, got ${{#rsp_files[@]}}: ${{HOSTLDFLAGS}}" >&2
            exit 1
        fi
        rsp1="${{rsp_files[0]}}"
        if [[ "${{rsp1}}" != "${{COMMON_OUT_DIR}}"/.kleaf_host_rpaths_*.rsp ]]; then
            echo "ERROR: Response file not in COMMON_OUT_DIR: ${{rsp1}}" >&2
            exit 1
        fi
        if [[ ! -f "${{rsp1}}" ]]; then
            echo "ERROR: Response file missing: ${{rsp1}}" >&2
            exit 1
        fi
        if ! grep -q '^-rpath=\\$ORIGIN/\\.\\./' "${{rsp1}}"; then
            echo "ERROR: Expected literal -rpath=\\$ORIGIN/../ entry in ${{rsp1}}, got contents:" >&2
            cat "${{rsp1}}" >&2
            exit 1
        fi

        # 3. Re-evaluating with the same OUT_DIR must be idempotent.
        before_ldflags="${{HOSTLDFLAGS}}"
        kleaf_internal_eval_ldflags
        if [[ "${{HOSTLDFLAGS}}" != "${{before_ldflags}}" ]]; then
            echo "ERROR: kleaf_internal_eval_ldflags is not idempotent" >&2
            exit 1
        fi

        # 4. Switching COMMON_OUT_DIR/OUT_DIR (simulating cache_dir) appends a
        #    second response file and still leaves zero '$' in HOSTLDFLAGS.
        export COMMON_OUT_DIR="${{PWD}}/out/test_hostldflags_cache/abcd1234"
        export OUT_DIR="${{COMMON_OUT_DIR}}/common"
        kleaf_internal_eval_ldflags
        if [[ "${{HOSTLDFLAGS}}" == *'$'* ]]; then
            echo "ERROR: HOSTLDFLAGS contains '$' after OUT_DIR change: ${{HOSTLDFLAGS}}" >&2
            exit 1
        fi
        rsp_files=()
        for tok in ${{HOSTLDFLAGS}}; do
            if [[ "${{tok}}" == -Wl,@* ]]; then
                rsp_files+=("${{tok#-Wl,@}}")
            fi
        done
        if [[ "${{#rsp_files[@]}}" -ne 2 ]]; then
            echo "ERROR: Expected 2 -Wl,@ response files after OUT_DIR change, got ${{#rsp_files[@]}}" >&2
            exit 1
        fi
        if [[ ! -f "${{rsp_files[1]}}" ]]; then
            echo "ERROR: Second response file missing: ${{rsp_files[1]}}" >&2
            exit 1
        fi

        # 5. Verify external output root (non-empty relative_to_output_suffix)
        #    produces -rpath=$ORIGIN/<backtrack>/<suffix>/<runpath> without '//'.
        (
            export ROOT_DIR="${{PWD}}/fake_sub/execroot"
            export COMMON_OUT_DIR="${{PWD}}/out/test_ext_cache/ef567890"
            export OUT_DIR="${{COMMON_OUT_DIR}}/common"
            mkdir -p "${{ROOT_DIR}}"
            kleaf_internal_eval_ldflags
            ext_rsp=""
            for tok in ${{HOSTLDFLAGS}}; do
                if [[ "${{tok}}" == -Wl,@"${{COMMON_OUT_DIR}}"/.kleaf_host_rpaths_*.rsp ]]; then
                    ext_rsp="${{tok#-Wl,@}}"
                fi
            done
            if [[ -z "${{ext_rsp}}" ]] || [[ ! -f "${{ext_rsp}}" ]]; then
                echo "ERROR: External output root response file missing" >&2
                exit 1
            fi
            if ! grep -q '^-rpath=\\$ORIGIN/\\.\\./fake_sub/execroot/' "${{ext_rsp}}"; then
                echo "ERROR: Expected -rpath=\\$ORIGIN/../fake_sub/execroot/ in ${{ext_rsp}}, got contents:" >&2
                cat "${{ext_rsp}}" >&2
                exit 1
            fi
            if grep -q '//' "${{ext_rsp}}"; then
                echo "ERROR: Unexpected '//' in ${{ext_rsp}}, got contents:" >&2
                cat "${{ext_rsp}}" >&2
                exit 1
            fi
        )

        # 6. Link and execute a musl host binary via both:
        #    (a) 1-expansion Make ($(HOSTLDFLAGS), like tools/objtool/Makefile)
        #    (b) 2-expansion Kbuild Make (KBUILD_HOSTLDFLAGS := $(HOSTLDFLAGS) -> sub-make)
        work_dir="${{OUT_DIR}}/tools/objtool"
        mkdir -p "${{work_dir}}"
        cat > "${{work_dir}}/main.c" <<'EOF'
#include <stdio.h>
int main(void) {{
    puts("hostldflags-ok");
    return 0;
}}
EOF

        cat > "${{work_dir}}/Makefile.direct" <<'EOF'
OBJTOOL_LDFLAGS := $(HOSTLDFLAGS)
all:
	clang $(HOSTCFLAGS) $(OBJTOOL_LDFLAGS) main.c -o prog_direct
EOF

        cat > "${{work_dir}}/Makefile.top" <<'EOF'
KBUILD_HOSTLDFLAGS := $(HOSTLDFLAGS)
export KBUILD_HOSTLDFLAGS
all:
	$(MAKE) -s -f Makefile.sub
EOF

        cat > "${{work_dir}}/Makefile.sub" <<'EOF'
all:
	clang $(HOSTCFLAGS) $(KBUILD_HOSTLDFLAGS) main.c -o prog_kbuild
EOF

        make -s -C "${{work_dir}}" -f Makefile.direct
        make -s -C "${{work_dir}}" -f Makefile.top

        for bin in "${{work_dir}}/prog_direct" "${{work_dir}}/prog_kbuild"; do
            runpath="$(llvm-readelf -d "${{bin}}" | grep -E 'RUNPATH|RPATH')"
            if [[ "${{runpath}}" != *'$ORIGIN/'* ]]; then
                echo "ERROR: ${{bin}} missing literal \\$ORIGIN in RUNPATH: ${{runpath}}" >&2
                exit 1
            fi
            if [[ "${{runpath}}" == *'{{ORIGIN}}'* ]]; then
                echo "ERROR: ${{bin}} has corrupted {{ORIGIN}} in RUNPATH: ${{runpath}}" >&2
                exit 1
            fi
            if [[ "$("${{bin}}")" != "hostldflags-ok" ]]; then
                echo "ERROR: Failed executing ${{bin}}" >&2
                exit 1
            fi
        done

        touch {out}
    """.format(
        hermetic_setup = hermetic_tools.setup,
        toolchains_setup = toolchains.kernel_setup_env_var_cmd,
        out = out.path,
    )

    ctx.actions.run_shell(
        mnemonic = "VerifyHostLdflags",
        outputs = [out],
        tools = depset(transitive = [
            hermetic_tools.deps,
            toolchains.all_files,
        ]),
        command = command,
    )
    return DefaultInfo(files = depset([out]))

_verify_hostldflags = rule(
    implementation = _verify_hostldflags_impl,
    attrs = {
        "_toolchains": attr.label(
            default = "//build/kernel/kleaf/impl:kernel_toolchains",
            providers = [KernelEnvToolchainsInfo],
        ),
    },
    toolchains = [hermetic_toolchain.type],
)

def kernel_hostldflags_test(name):
    """Defines test for HOSTLDFLAGS response file behavior.

    Args:
        name: Name of the test target.
    """
    _verify_hostldflags(
        name = name + "_verify",
        tags = ["manual"],
    )

    build_test(
        name = name,
        targets = [":" + name + "_verify"],
    )
