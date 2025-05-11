# Chomp
### (CHromeOS on Modern Platforms)
A shim modification tool that allows you to boot ChromeOS shims on UEFI enabled platforms.

## How to build
`# bash build.sh [shim.bin]` (# denoting root.)

To use Chomp with shim modification tools (i.e, SH1MMER's wax), you need to modify their<br>
respective builders in order to not delete partition 12.

# Credits
 - xmb9: Gave birth to CHOMP
 - kxtzownsu: this project wouldn't exist without him; got the first ever shim on uefi working, made picoshim, testing
 - vk6: made extract_initramfs.sh
