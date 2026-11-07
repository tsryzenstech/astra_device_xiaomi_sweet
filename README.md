# astraOS for Xiaomi Redmi Note 10 Pro (sweet)

Build system for a flashable [astraOS](../astra) image for the Redmi Note 10
Pro / Pro Max (`sweet`, `sweetin`, Snapdragon 732G / SM7150).

It produces the usual fastboot images:

| Image | Contents |
|---|---|
| `u-boot.img` | [astraOS's U-Boot](https://github.com/tsryzenstech/u-boot/tree/astra) (sm7150-mainline's, silent, without logos), flashed to `boot` |
| `userdata.img` | start of `userdata`: GPT (4096 byte sectors) with the EFI partition `astra_esp` holding `\EFI\BOOT\BOOTAA64.EFI`, a unified kernel image (kernel, ramdisk, command line) |
| `boot.img` | the same kernel and ramdisk for the stock bootloader (header v2), used with `--stock-boot` |
| `boot-debug.img`, `boot-rescue.img` | for `fastboot boot` only: every kernel message on screen / USB rescue mode with a logs drive |
| `super.img` | dynamic partitions `system`, `vendor`, `product` (sparse, group `qti_dynamic_partitions`) |
| `vbmeta.img` | empty vbmeta, verification disabled |

There is no `dtbo.img`: the flash scripts **erase** the `dtbo` partition.
The stock overlays target the downstream kernel, and the bootloader goes
straight back to fastboot when a valid overlay table has no entry for the
board, which an erased partition avoids.

> **Status: Developer Preview.** On the phone (M2101K6G, panel `38-0c-0a`) the
> logo, user interface and touch have worked with these steps run by hand. Keep a
> stock/MIUI fastboot ROM at hand to go back. What the phone needs, all in
> [`sweet.rc`](rootdir/vendor/etc/init/sweet.rc):
>
> - **The hardware watchdog's driver, first.** The bootloader leaves the watchdog
>   running. Without `qcom_wdt` the phone freezes at about 30 s and resets at
>   about 50 s, whatever is running.
> - **Two DSC slices per packet.** The panel stays black or shows garbage with the
>   one the kernel's DSI driver sends. Until the driver can do it, `disptest
>   setreg` writes the register from userspace; the proper fix is a kernel patch.
> - **120 Hz only**, because a modeset to another rate resets that register. With
>   all the drivers loaded, modesets and blanking the framebuffer also froze the
>   phone (seen before the interconnect correction below; not tried again since).
> - **A corrected device tree**, [`dtbfix.py`](scripts/dtbfix.py). `sm7150.dtsi`
>   names QUP1's interconnect endpoint on the wrong provider, so nothing keeps
>   QUP1's bus clock on once `sync_state` has dropped the bootloader's votes: the
>   first access to i2c7, where the touchscreen is, stopped the CPU. The first touch
>   froze the phone. Tried on the phone: the touch works with the correction, with
>   nothing else changed. It belongs upstream in the kernel's device tree.
>
> - **hexagonrpcd must not write to the kernel log.** The ADSP's sensor process asks
>   it for files. With its output on the kernel log, where init puts services, that
>   process stalls and takes the ADSP down about every 40 s, and two freezes ended
>   right after such a restart. With its output elsewhere: no crash at all.
> - **The speaker amplifiers** bind to the aw88261 driver (`dtbfix.py`) with the
>   calibration file from the stock ROM (`board.conf`). The sound card appears and
>   the clocks reach the amplifier, but it reports a boost over-current and does not
>   start. **There is no sound from the speaker yet.**
>
> Not working yet: speaker and microphone, camera, fingerprint. Bluetooth's controller
> gets its address in `launch.sh`, the firmware in `build-rootfs.sh`; turning it on
> was tried by hand, audio over it not yet.

## What stays fixed

The system is astraOS's own init on Alpine Linux libraries. These are pinned so
that two builds are the same, not because this combination is known to work:

| Part | Pinned to | Where |
|---|---|---|
| Kernel | sm7150-mainline `v7.1_rc3`, the binary package, checksum verified | [`kernel/prebuilt`](kernel/prebuilt), [`board.conf`](board.conf) |
| U-Boot | commit of [tsryzenstech/u-boot](https://github.com/tsryzenstech/u-boot/tree/astra) | `UBOOT_REF` |
| Device firmware | commit of `sm7150-mainline/firmware-xiaomi-sweet` | `FIRMWARE_REF` |
| Mesa 25.1.9, Qt 6.8.3, LLVM, musl, libdrm, firmware... | exact Alpine v3.22 versions | [`packages.lock`](packages.lock) (`critical`) |

Alpine removes a version from its mirror when it replaces it. When that happens
to a critical package the build **stops**: decide then whether to move to the new
version.

Before anything is packaged, [`scripts/verify.py`](scripts/verify.py) checks the
finished images, and a failure stops the build: the pins above, that every
program finds its libraries and every QML import its module, the first stage
and GPU firmware in the ramdisk, the unified kernel image (kernel, ramdisk and
command line) read back from `userdata.img`, the contents of the ext4 images,
and SysBoard's QML loaded on this Qt without a display. The report is
`verify.txt` in the zip and in the release notes. It cannot see how the
hardware behaves: only booting the phone can.

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

The zip lands in `out/astraOS-<version>-sweet.zip`.

Steps can be run one at a time: `./build.sh --docker fetch kernel uboot astra llama rootfs images verify package`.

### Without Docker (e.g. WSL)

```bash
sudo apt install qemu-user-static binfmt-support
./build.sh                # asks for sudo: everything runs in an Alpine aarch64 chroot
```

## What the build does

1. **fetch** – astraOS and the device firmware
   (`sm7150-mainline/firmware-xiaomi-sweet`, non-free, downloaded at build
   time and never committed here).
2. **kernel** – by default the kernel package in
   [`kernel/prebuilt`](kernel/prebuilt), checked against `KERNEL_PACKAGE_SHA256` and unpacked (image, device
   tree, modules). `KERNEL_SOURCE=source` builds sm7150-mainline instead, from
   `defconfig` + `sm7150.config` + [`kernel/astra.config`](kernel/astra.config)
   Either way the uncompressed kernel must stay under 31 MB: the bootloader
   puts the device tree right after that and a bigger kernel overwrites it.
3. **astra** – builds the astraOS system code natively for aarch64/musl
   (static `init` for the ramdisk).
4. **rootfs** – installs the userland libraries (musl, Mesa, Qt 6...) from
   Alpine packages ([`packages.txt`](packages.txt)) and relocates them into
   the astraOS layout (`/system/{bin,lib,etc}`, with `/bin`, `/lib`, `/etc`,
   `/usr` as symlinks), adds astraOS, kernel modules, the vendor partition
   ([`rootdir/vendor`](rootdir/vendor)) and the ramdisk.
5. **uboot** – clones [tsryzenstech/u-boot](https://github.com/tsryzenstech/u-boot/tree/astra)
   (`UBOOT_REPO`, commit `UBOOT_REF`), builds it with `astra.config` for
   `sm7150-xiaomi-sweet` and wraps it for the stock bootloader (`u-boot.img`).
6. **images** – ext4 images, `userdata.img` (EFI partition with the unified
   kernel image, made with `ukify`), `boot.img` (stock ABL parameters, see
   [`board.conf`](board.conf)), `super.img` with `lpmake`, `vbmeta.img`.
7. **verify** – [`scripts/verify.py`](scripts/verify.py), see above.
8. **package** – zip with the images, `u-boot.img` and the flashing scripts;
   it refuses images that did not pass **verify**.

### How the phone boots

The stock bootloader starts **U-Boot** from `boot`. U-Boot maps `userdata`
as a disk (its first 128 MiB are `userdata.img`) and starts the EFI
application of its EFI partition: astraOS's kernel with the ramdisk and the
command line. astraOS's first stage init maps the dynamic partitions of
`super`, and maps the rest of `userdata` (after the first 128 MiB) as
`/data`. U-Boot shows nothing:
hold **Volume Down** while the phone starts for its boot menu (also shown
when a boot fails).

## Flash

Boot the phone into fastboot (Volume down + Power), connect it and run from
the extracted package:

```bash
./flash-all.sh --wipe      # first install: erases userdata
./flash-all.sh             # updates, keeps your data
```

On Windows use `flash-all.bat` (same arguments). They flash `u-boot.img` to
`boot`, `super.img`, and `userdata.img` to the start of `userdata`; with
`--wipe`, `userdata-wipe.img` instead, which also clears where `/data`
starts, and the first boot formats `/data` as ext4. (The whole of `userdata`
is never erased: on this UFS it takes longer than fastboot waits over USB.) `--stock-boot` flashes `boot.img`
instead, started by the stock bootloader without U-Boot.

To go back to MIUI/HyperOS, flash a stock fastboot ROM with Xiaomi's tool.

### If it does not boot

- To try a build without flashing `boot`, run `fastboot boot boot.img`
  (after flashing `super`, `vbmeta` and erasing `dtbo`).
- Nothing is printed on the screen while the phone starts: U-Boot's boot menu
  (hold Volume Down) shows the last boot's log.
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
- **To see the system from a computer:** `flash-diag.bat` (or `./flash-diag.sh`)
  erases the phone and flashes `userdata-diag.img`, the same system with
  `astra.diag` on the kernel command line: a root shell on the USB serial port and
  the kernel log in `/data/diag`, synced every 2 s so that a freeze leaves its last
  messages behind. `disptest` tests the display by hand. A normal
  `flash-all --wipe` goes back.

## Device notes

| | |
|---|---|
| SoC | Qualcomm SM7150-AC (Snapdragon 732G), Adreno 618 |
| Display | 1080 × 2400 AMOLED (`samsung,ams667yr01`), UI scale 2.75 |
| Touch | Goodix GT9896 |
| Partitions | A-only, dynamic partitions in `super` (9126805504 bytes) |
| Boot chain | stock ABL → U-Boot (`u-boot.img`, header v0, base 0x0, page size 4096) → EFI (`userdata.img`); `boot.img` is header v2 with `Image.gz` + DTB |

## Layout of this repository

```
board.conf            device parameters (kernel, boot image, super)
packages.txt          Alpine packages providing the userland libraries
packages.lock         their pinned versions
scripts/build-qcom-tools.sh  rmtfs and tqftpserv, which bring the modem up
kernel/prebuilt/      the tested kernel package
kernel/astra.config   kernel configuration fragment (KERNEL_SOURCE=source)
rootdir/vendor/       vendor partition: fstab, init scripts
scripts/              build steps
flash/                fastboot flashing scripts shipped in the package
Dockerfile            build environment (Alpine aarch64)
```

## License

Build scripts and configuration: [Apache License 2.0](LICENSE). Firmware
and Alpine packages keep their own licenses.

The kernel in `kernel/prebuilt` is licensed under the GPL version 2. It was
built by the [postmarketOS](https://postmarketos.org) team, whom we thank for
their work on SM7150 phones, from the sources of
[sm7150-mainline/linux](https://github.com/sm7150-mainline/linux) (tag
`v7.1_rc3`); its configuration is `/boot/config` in the package.
