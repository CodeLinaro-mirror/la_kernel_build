#!/bin/bash
#
# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
# SPDX-License-Identifier: BSD-3-Clause-Clear

#set -x
BASE=$(dirname $(dirname $(dirname $(readlink -f $0))))

echo $BASE

pushd $BASE > /dev/null

rm WORKSPACE

ln -s build/kernel/kleaf/bazel.WORKSPACE WORKSPACE
rm -rf kernel/trout_virtio_kernel

tools/bazel clean --expunge

tools/bazel run //common-modules/virtual-device:virtual_device_aarch64_dist  -- --dist_dir=kernel/trout_virtio_kernel

rm WORKSPACE

popd > /dev/null
