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
echo "kxtzownsu: got the first ever shim on uefi working, made picoshim, testing"
echo "vk6: made extract_initramfs.sh"

echo "Requirements:"
echo "binwalk v2, vboot-utils"

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

rm -rf "$initramfs"
rm -rf /tmp/shim_kernel/
rm -rf /tmp/kernel.bin

echo "GRUB"

rootuuid=$(blkid -s PARTUUID -o value "$loopdev"p3)
kernguid=$(blkid -s PARTUUID -o value "$loopdev"p2)

args=$(vbutil_kernel --verify "$loopdev"p2 | sed -n '/^Config:/,$p' | sed '1s/^Config:[[:space:]]*//' | sed -E "s#root=[^ ]+#root=PARTUUID=${rootuuid}#" | sed -E "s#kern_guid=[^ ]+#kern_guid=${kernguid}#" | awk '{$1=$1};1')

args+=" cros_debug"

export args

echo "boot arguments: ${args}"

mkdir /tmp/grubmount
mount "$loopdev"p12 /tmp/grubmount

cp initramfs.cpio.gz /tmp/grubmount/syslinux/

read -r -d '' chomp_grubentry << 'EOF'
menuentry "Chomp injected shim" {
   linux /syslinux/vmlinuz.A ${args}
   echo "Injecting Chomp as initramfs..."
   initrd /syslinux/initramfs.cpio.gz
}
EOF

chomp_grubentry=$(echo "$chomp_grubentry" | envsubst)

awk -v replacement="$chomp_grubentry" '
  BEGIN { in_block=0 }
  /^menuentry "local image A"/ { in_block=1; print replacement; next }
  in_block && /^}/ { in_block=0; next }
  !in_block
' /tmp/grubmount/efi/boot/grub.cfg > /tmp/grubmount/efi/boot/grub.cfg.new && mv /tmp/grubmount/efi/boot/grub.cfg.new /tmp/grubmount/efi/boot/grub.cfg

rm initramfs.cpio.gz

losetup -D

echo "Done!"
