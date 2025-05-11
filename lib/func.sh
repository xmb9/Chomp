#!/bin/bash

is_ext2() {
	local rootfs="$1"
	local offset="${2-0}"

	local sb_magic_offset=$((0x438))
	local sb_value=$(dd if="$rootfs" skip=$((offset + sb_magic_offset)) \
		count=2 bs=1 2>/dev/null)
	local expected_sb_value=$(printf '\123\357')
	if [ "$sb_value" = "$expected_sb_value" ]; then
		return 0
	fi
	return 1
}

enable_rw_mount() {
	local rootfs="$1"
	local offset="${2-0}"

	if ! is_ext2 "$rootfs" $offset; then
		echo "enable_rw_mount called on non-ext2 filesystem: $rootfs $offset" 1>&2
		return 1
	fi

	local ro_compat_offset=$((0x464 + 3))
	printf '\000' |
		dd of="$rootfs" seek=$((offset + ro_compat_offset)) \
			conv=notrunc count=1 bs=1 2>/dev/null
} # https://github.com/MercuryWorkshop/sh1mmer/
