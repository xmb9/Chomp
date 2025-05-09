#!/bin/bash

COLOR_RESET="\033[0m"
COLOR_BLACK_B="\033[1;30m"
COLOR_RED_B="\033[1;31m"
COLOR_GREEN="\033[0;32m"
COLOR_GREEN_B="\033[1;32m"
COLOR_YELLOW="\033[0;33m"
COLOR_YELLOW_B="\033[1;33m"
COLOR_BLUE_B="\033[1;34m"
COLOR_MAGENTA_B="\033[1;35m"
COLOR_CYAN_B="\033[1;36m"

fail() {
	printf "${COLOR_RED_B}%b${COLOR_RESET}\n" "$*" >&2 || :
	exit 1
}

if [[ $EUID -ne 0 ]]; then
   fail "This script must be run as root"
fi

VERSION="v1.00"

echo "CHOMP builder ${VERSION}"

echo "Credits:"
echo "xmb9: Gave birth to CHOMP"
echo "kxtzownsu: extract_initramfs.sh, PicoShim"

SHIM="$1"
initramfs="/tmp/chomp_initramfs"

mkdir "$initramfs"

loopdev=$(losetup -f)

source lib/extract_initramfs.sh

if ! $(losetup | grep loop0); then
	touch /tmp/loop0
	dd if=/dev/urandom of=/tmp/loop0 bs=1 count=512 status=none > /dev/null 2>&1
	losetup -P /dev/loop0 /tmp/loop0
fi

loopdev=$(losetup -f)

losetup -P "$loopdev" "$SHIM"

extract_initramfs_full "$loopdev" "$initramfs" "/tmp/shim_kernel/kernel.img" "x86_64"

echo "Injecting CHOMP... (this is where the magic happens)"
cp -r scripts/* "$initramfs"/

echo "Creating initramfs."

prev=$(pwd)

cd "$initramfs"

find . -print0 | cpio --null -ov --format=newc > "$prev"/initramfs.cpio
echo "If all looks good here, and if prompted to overwrite, press \"y\""
gzip "$prev"/initramfs.cpio

cd "$prev"

echo "Done building initramfs."

losetup -D
rm -rf "$initramfs"
rm -rf /tmp/shim_kernel/
rm -rf /tmp/kernel.bin

echo "Need to figure out grub next..."
