#!/bin/bash
#
# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
# SPDX-License-Identifier: BSD-3-Clause-Clear

#set -x

cleanup() {
    printf "Received ERR/INT....Exiting build_trout_kernel.sh\n"
    exit 1
}

trap cleanup INT ERR

BASE=$(dirname $(dirname $(dirname $(readlink -f $0))))
KERNEL_VENDOR_DTS_PATH=$BASE/kernel_platform/msm-kernel/arch/arm64/boot/dts/vendor
KERNEL_INCLUDE_PATH=$BASE/kernel_platform/msm-kernel/include
KERNEL_OUT=$BASE/device/common/kalama-kernel

mkdir -p $KERNEL_OUT

echo "BASE=$BASE"
echo "KERNEL_OUT=$KERNEL_OUT"

pushd $BASE > /dev/null

rm -rf $KERNEL_OUT
rm -f WORKSPACE

ln -s build/kernel/kleaf/bazel.WORKSPACE WORKSPACE

if [ "${RECOMPILE_KERNEL}" == "1" ]; then
    # remove all trace of previously built kernel
    echo "cleaning previously built kernel"
    tools/bazel clean --expunge
else
    #bazel tool will simply just copy a previously built kernel to the target directory.
    echo "re-using previous build"
fi

tools/bazel run //common-modules/virtual-device:virtual_device_aarch64_dist  -- --dist_dir=$KERNEL_OUT

rm -f WORKSPACE

# Generate kalama-vm-cdp.dtb needed for by ghgvm-pilsplitter.sh tool.

IDE=kalama-vm-cdp
SRC=$KERNEL_VENDOR_DTS_PATH/qcom/$IDE.dts
TMP=$KERNEL_OUT/$IDE.tmp.dts
DST=$KERNEL_OUT/dtbs/$IDE.dtb

rm -rf $KERNEL_OUT/dtbs
mkdir -p $KERNEL_OUT/dtbs

cpp -nostdinc -I $KERNEL_INCLUDE_PATH -undef -x assembler-with-cpp $SRC > $TMP
dtc -O dtb -b 0 -o $DST $TMP

rm -f $TMP

#Remove all Android.mk and Android.bp files from source so they don't conflict with Android's
#As not building for the current component in these folders, have no affect but references.
find ${BASE}/vendor/qcom \( -name Android.mk -o -name Android.bp \) \
    -a -not -path ${BASE}/common/Android.bp -a -not -path ${BASE}/kernel_platform/msm-kernel/Android.bp \
    -delete
set +x

popd > /dev/null
