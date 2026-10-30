# astraOS for Xiaomi Redmi Note 10 Pro (sweet)

Build system for a flashable [astraOS](../astra) image for the Redmi Note 10
Pro / Pro Max (`sweet`, `sweetin`, Snapdragon 732G / SM7150).

It produces the usual fastboot images:

| Image | Contents |
|---|---|
| `boot.img` | postmarketOS's SM7150 mainline kernel, `sm7150-xiaomi-sweet.dtb`, ramdisk with astra first stage init (header v2) |
| `super.img` | dynamic partitions `system`, `vendor`, `product` (sparse, group `qti_dynamic_partitions`) |
| `vbmeta.img` | empty vbmeta, verification disabled |

There is no `dtbo.img`: the flash scripts **erase** the `dtbo` partition.
The stock overlays target the downstream kernel, and the bootloader goes
straight back to fastboot when a valid overlay table has no entry for the
board, which an erased partition avoids.

> **Status: Developer Preview, not yet booted on hardware.** The build is
> complete, but expect a bring-up phase (display, touch, GPU firmware) before
> the first successful boot. Keep a stock/MIUI fastboot ROM at hand to go
> back.

## Requirements

- An **unlocked bootloader** (Xiaomi unlock tool).
- To build: an arm64 Linux machine with Docker, or any Linux/WSL2 machine
  with Docker + `qemu-user-static` (slower), or a root shell for the
  chroot-based build (see below). GitHub Actions builds it on native arm64
  runners (`.github/workflows/build.yml`).
- About 15 GB of free disk space.

## Build

Clone this repository next to the `astra` repository (it is picked up
automatically; otherwise it is cloned from `ASTRA_REPO`):

```
GitHub/
├── astra/
└── astra_device_xiaomi_sweet/
```

```bash
./build.sh --docker
```

The zip lands in `out/astraOS-<version>-sweet-<date>.zip`.

Steps can be run one at a time: `./build.sh --docker fetch kernel astra rootfs images package`.

### Without Docker (e.g. WSL)

```bash
sudo apt install qemu-user-static binfmt-support gcc-aarch64-linux-gnu bc bison flex libssl-dev libelf-dev
sudo scripts/chroot.sh setup                              # Alpine aarch64 build root
./build.sh fetch
CROSS_COMPILE=aarch64-linux-gnu- ./build.sh kernel       # fast: cross compiled on the host
sudo scripts/chroot.sh build astra rootfs images package
```

## What the build does

1. **fetch** – astraOS and the device firmware
   (`sm7150-mainline/firmware-xiaomi-sweet`, non-free, downloaded at build
   time and never committed here).
2. **kernel** – by default the prebuilt kernel postmarketOS ships for SM7150
   phones (`linux-postmarketos-qcom-sm7150`, sm7150-mainline 7.1-rc3, the one
   known to boot sweet with its display): downloaded from the postmarketOS
   mirror, checked against `PMOS_KERNEL_SHA256`, and unpacked (image, device
   tree, modules). `KERNEL_SOURCE=source` builds sm7150-mainline instead, from
   `defconfig` + `sm7150.config` + [`kernel/astra.config`](kernel/astra.config).
   Either way the uncompressed kernel must stay under 31 MB: the bootloader
   puts the device tree right after that and a bigger kernel overwrites it.
3. **astra** – builds the astraOS system code natively for aarch64/musl
   (static `init` for the ramdisk).
4. **rootfs** – installs the userland libraries (musl, Mesa, Qt 6...) from
   Alpine packages ([`packages.txt`](packages.txt)) and relocates them into
   the astraOS layout (`/system/{bin,lib,etc}`, with `/bin`, `/lib`, `/etc`,
   `/usr` as symlinks), adds astraOS, kernel modules, the vendor partition
   ([`rootdir/vendor`](rootdir/vendor)) and the ramdisk.
5. **images** – ext4 images, `boot.img` (stock ABL parameters, see
   [`board.conf`](board.conf)), `super.img` with `lpmake`, `vbmeta.img`.
6. **package** – zip with the images and flashing scripts.

## Flash

Boot the phone into fastboot (Volume down + Power), connect it and run from
the extracted package:

```bash
./flash-all.sh --wipe      # first install: erases userdata
./flash-all.sh             # updates, keeps your data
```

On Windows use `flash-all.bat` (same arguments). The first boot formats
`/data` as ext4.

To go back to MIUI/HyperOS, flash a stock fastboot ROM with Xiaomi's tool.

### If it does not boot

- To try a build without flashing `boot`, run `fastboot boot boot.img`
  (after flashing `super`, `vbmeta` and erasing `dtbo`).
- Kernel messages are shown on the screen while the phone starts.
- When astraOS cannot mount its partitions it **stays on screen** with the
  reason and the end of the kernel log, instead of rebooting. It also opens
  a rescue shell over USB: a new serial port appears on the computer
  (`/dev/ttyACM0` on Linux and macOS, a COM port on Windows; any baud rate).
  Use `dmesg`, `cat /proc/partitions` there, and share the output.
- The previous boot's kernel log is in `/sys/fs/pstore` on the next boot.
- **The screen goes dark after the logo, with no text:** start
  `fastboot boot boot-debug.img`. It prints every kernel message on the
  screen: a photo of the last lines shows where the boot stops.
- **To get a shell:** after a failed boot, hold power + volume down to reach
  fastboot and start `fastboot boot boot-rescue.img`. It stops in the first
  stage with the USB rescue shell; there, `dmesg` and
  `cat /sys/fs/pstore/*` (the failed boot's log) tell what happened.
  `boot-debug.img` and `boot-rescue.img` are never flashed.

## Device notes

| | |
|---|---|
| SoC | Qualcomm SM7150-AC (Snapdragon 732G), Adreno 618 |
| Display | 1080 × 2400 AMOLED (`samsung,ams667yr01`), UI scale 2.75 |
| Touch | Goodix GT9896 |
| Partitions | A-only, dynamic partitions in `super` (9126805504 bytes) |
| Boot image | header v2, base 0x0, page size 4096, `Image.gz` + DTB |

## Layout of this repository

```
board.conf            device parameters (kernel, boot image, super)
packages.txt          Alpine packages providing the userland libraries
kernel/astra.config   kernel configuration fragment
rootdir/vendor/       vendor partition: fstab, init scripts
scripts/              build steps
flash/                fastboot flashing scripts shipped in the package
Dockerfile            build environment (Alpine aarch64)
```

## License

Build scripts and configuration: [Apache License 2.0](LICENSE). Firmware
and Alpine packages keep their own licenses.
