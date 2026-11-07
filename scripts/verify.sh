#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Checks the finished images before they are packaged: see scripts/verify.py.
source "$(dirname "$0")/common.sh"
need python3 readelf debugfs mdir zstd

export DEVICE_DIR OUT SRC STAGE SYSTEM_ROOT VENDOR_ROOT PRODUCT_ROOT RAMDISK IMAGES
export ALPINE_BRANCH BOOT_CMDLINE KERNEL_DTB KERNEL_RELEASE KERNEL_SOURCE KERNEL_PACKAGE KERNEL_PACKAGE_SHA256
export UBOOT_REF FIRMWARE_REF AW_ACF_SHA256 STORAGE_SECTOR_SIZE SUPER_GROUP_SIZE SUPER_PARTITIONS
ASTRA_SOURCE=$(astra_source)
export ASTRA_SOURCE
exec python3 "$DEVICE_DIR/scripts/verify.py"
