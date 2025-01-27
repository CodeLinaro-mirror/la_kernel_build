load("@kleaf//build/kernel/kleaf/impl:openssl/configure_and_make.bzl", "configure_and_make")

package(default_visibility = ["//visibility:public"])

_BIN = [
    "c_rehash",
    "openssl",
]

_INCLUDE = [
    "pem2.h",
    "cast.h",
    "cryptoerr.h",
    "fipskey.h",
    "rc4.h",
    "cmp_util.h",
    "camellia.h",
    "sslerr.h",
    "hmac.h",
    "comp.h",
    "md5.h",
    "store.h",
    "http.h",
    "decodererr.h",
    "asn1err.h",
    "tls1.h",
    "des.h",
    "rsa.h",
    "safestack.h",
    "httperr.h",
    "blowfish.h",
    "decoder.h",
    "cmperr.h",
    "ssl2.h",
    "e_os2.h",
    "modes.h",
    "bioerr.h",
    "configuration.h",
    "core_names.h",
    "cterr.h",
    "pem.h",
    "dsaerr.h",
    "opensslconf.h",
    "x509v3err.h",
    "dherr.h",
    "ossl_typ.h",
    "engineerr.h",
    "kdf.h",
    "md4.h",
    "pkcs12err.h",
    "conf_api.h",
    "ecdsa.h",
    "x509.h",
    "asn1t.h",
    "asn1.h",
    "asyncerr.h",
    "randerr.h",
    "evp.h",
    "opensslv.h",
    "conftypes.h",
    "params.h",
    "x509_vfy.h",
    "ebcdic.h",
    "ocsperr.h",
    "objects.h",
    "cryptoerr_legacy.h",
    "cms.h",
    "async.h",
    "comperr.h",
    "seed.h",
    "dsa.h",
    "provider.h",
    "esserr.h",
    "srtp.h",
    "storeerr.h",
    "idea.h",
    "types.h",
    "dh.h",
    "uierr.h",
    "ssl3.h",
    "ripemd.h",
    "ecerr.h",
    "evperr.h",
    "pkcs7.h",
    "srp.h",
    "pemerr.h",
    "conferr.h",
    "x509v3.h",
    "trace.h",
    "ui.h",
    "kdferr.h",
    "whrlpool.h",
    "ocsp.h",
    "ts.h",
    "prov_ssl.h",
    "macros.h",
    "bn.h",
    "ec.h",
    "objectserr.h",
    "asn1_mac.h",
    "rsaerr.h",
    "ct.h",
    "crmf.h",
    "engine.h",
    "mdc2.h",
    "err.h",
    "core_object.h",
    "txt_db.h",
    "stack.h",
    "tserr.h",
    "cmp.h",
    "crmferr.h",
    "crypto.h",
    "x509err.h",
    "cmac.h",
    "buffererr.h",
    "sha.h",
    "rc2.h",
    "rand.h",
    "encoder.h",
    "encodererr.h",
    "param_build.h",
    "lhash.h",
    "ess.h",
    "symhacks.h",
    "ssl.h",
    "core_dispatch.h",
    "md2.h",
    "bnerr.h",
    "rc5.h",
    "core.h",
    "buffer.h",
    "conf.h",
    "bio.h",
    "cmserr.h",
    "fips_names.h",
    "aes.h",
    "pkcs7err.h",
    "self_test.h",
    "obj_mac.h",
    "ecdh.h",
    "pkcs12.h",
    "dtls1.h",
    "sslerr_legacy.h",
    "proverr.h",
]

_LIB64 = [
    "libssl.so",
    "libssl.so.3",
    "libcrypto.so",
    "libcrypto.so.3",
]

_CONFIGURE_OPTIONS = [
    # disabled because the toolchain's linker errors out
    "no-dynamic-engine",
]

_CFLAGS = [
    "-Wall",
    "-O3",
]

_LDFLAGS = []

configure_and_make(
    name = "configure-and-make",
    srcs = glob(["**"]),
    include = _INCLUDE,
    bin = _BIN,
    cflags = _CFLAGS,
    configure = glob(["Configure"])[0],
    configure_options = _CONFIGURE_OPTIONS,
    ldflags = _LDFLAGS,
    lib64 = _LIB64,
)

filegroup(
    name = "bin",
    srcs = [":" + t for t in _BIN],
    visibility = ["//visibility:public"],
)

filegroup(
    name = "include",
    srcs = [":" + t for t in _INCLUDE],
    visibility = ["//visibility:public"],
)

filegroup(
    name = "lib64",
    srcs = [":" + t for t in _LIB64],
    visibility = ["//visibility:public"],
)

cc_import(
    name = "libssl",
    shared_library = ":libssl.so",
    target_compatible_with = [
        "@platforms//os:linux",
        "@platforms//cpu:x86_64",
    ],
)

cc_import(
    name = "libcrypto",
    shared_library = ":libcrypto.so",
    target_compatible_with = [
        "@platforms//os:linux",
        "@platforms//cpu:x86_64",
    ],
)

cc_library(
    name = "openssl-library",
    hdrs = [":include"],
    include_prefix = "openssl",
    target_compatible_with = [
        "@platforms//os:linux",
        "@platforms//cpu:x86_64",
    ],
    visibility = ["//visibility:public"],
    deps = [
        ":libcrypto",
        ":libssl",
    ],
)
