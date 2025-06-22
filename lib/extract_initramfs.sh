#!/bin/bash

#utilties for reading shim disk images

run_binwalk() {
  if binwalk -h | grep -- '--run-as' >/dev/null; then
    binwalk "$@" --run-as=root
  else
    binwalk "$@"
  fi
}

extract_initramfs() {
  local kernel_bin="$1"
  local working_dir="$2"
  local output_dir="$3"

  #extract the compressed kernel image from the partition data
  local kernel_file="$(basename $kernel_bin)"
  local binwalk_out=$(run_binwalk --extract $kernel_bin --directory=$working_dir)
  local stage1_file=$(echo $binwalk_out | pcregrep -o1 "\d+\s+0x([0-9A-F]+)\s+gzip compressed data")
  local stage1_dir="$working_dir/_$kernel_file.extracted"
  local stage1_path="$stage1_dir/$stage1_file"


  #extract the initramfs cpio archive from the kernel image
  run_binwalk --extract $stage1_path --directory=$stage1_dir > /dev/null
  local stage2_dir="$stage1_dir/_$stage1_file.extracted/"
  local cpio_file=$(file $stage2_dir/* | pcregrep -o1 "([0-9A-F]+):\s+ASCII cpio archive")
  local cpio_path="$stage2_dir/$cpio_file"
  
  mkdir "$output_dir"
  
  local prev=$(pwd)
  cd "$output_dir"
  cpio -id < "$cpio_path"

  cd "$prev"
}

extract_initramfs_arm() {
  local kernel_bin="$1"
  local working_dir="$2"
  local output_dir="$3"

  #extract the kernel lz4 archive from the partition
  local binwalk_out="$(run_binwalk $kernel_bin)"
  local lz4_offset="$(echo "$binwalk_out" | pcregrep -o1 "(\d+).+?LZ4 compressed data" | head -n1)"
  local lz4_file="$working_dir/kernel.lz4"
  local kernel_img="$working_dir/kernel_decompressed.bin"
  dd if=$kernel_bin of=$lz4_file iflag=skip_bytes,count_bytes skip=$lz4_offset status=none
  lz4 -d $lz4_file $kernel_img -q || true

  #extract the initramfs cpio archive from the kernel image
  local extracted_dir="$working_dir/_kernel_decompressed.bin.extracted"
  run_binwalk --extract $kernel_img --directory=$working_dir > /dev/null
  local cpio_file=$(file $extracted_dir/* | pcregrep -o1 "([0-9A-F]+):\s+ASCII cpio archive")
  local cpio_path="$extracted_dir/$cpio_file"

  cat $cpio_path | cpio -D $output_dir -imd --quiet
}

create_loop() {
  local loop_device=$(losetup -f)
  if [ ! -b "$loop_device" ]; then
    #we might run out of loop devices, see https://stackoverflow.com/a/66020349
    local major=$(grep loop /proc/devices | cut -c3)
    local number="$(echo "$loop_device" | grep -Eo '[0-9]+' | tail -n1)"
    mknod $loop_device b $major $number
  fi
  losetup -P $loop_device "${1}"
  echo $loop_device
}

copy_kernel() {
  local shim_path="$1"
  local kernel_dir="$2"

  local shim_loop=$(create_loop "${shim_path}")
  local kernel_loop="${shim_loop}p2" #KERN-A should always be p2
  dd if=$kernel_loop of=$kernel_dir/kernel.bin bs=1M status=none
  dd if=$kernel_loop of="/tmp/kernel.bin" bs=1M status=none
  # losetup -d $shim_loop
}

#copy the kernel image then extract the initramfs
extract_initramfs_full() {
  local shim_path="$1"
  local rootfs_dir="$2"
  local kernel_bin="$3"
  local arch="$4"
  local kernel_dir=/tmp/shim_kernel

  echo "copying the shim kernel"
  rm -rf $kernel_dir
  mkdir $kernel_dir -p
  copy_kernel $shim_path $kernel_dir

  echo "extracting initramfs from kernel (this may take a while)"
  if [ "$arch" = "aarch64" ]; then
    extract_initramfs_arm $kernel_dir/kernel.bin $kernel_dir $rootfs_dir
  else
    extract_initramfs $kernel_dir/kernel.bin $kernel_dir $rootfs_dir
  fi


  if [ "$kernel_bin" ]; then 
    cp $kernel_dir/kernel.bin $kernel_bin
  fi
}
