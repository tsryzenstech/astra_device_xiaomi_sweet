# astraOS for Xiaomi Redmi Note 10 Pro (sweet)

Build system for a flashable [astraOS](https://github.com/tsryzenstech/astra)
for the Redmi Note 10 Pro / Pro Max (`sweet`, `sweetin`, Snapdragon 732G /
SM7150).

**astraOS on this phone is built on [postmarketOS](https://nura.eco)**
(renamed **Nura** in 2026). The kernel, initramfs, firmware, device support,
base system and init (OpenRC) are postmarketOS's, installed with
`pmbootstrap` the same way postmarketOS installs itself on SM7150 phones.
astraOS (astrad, SysBoard, the apps) runs on top as a postmarketOS package,
`astraos`, the way postmarketOS runs Phosh or Plasma Mobile.

| Image | Flashed to | Contents |
|---|---|---|
| `u-boot.img` | `boot` | [astraOS's U-Boot](https://github.com/tsryzenstech/u-boot/tree/astra): sm7150-mainline's U-Boot, as postmarketOS uses on this phone, but silent and without logos |
| `userdata.img` | `userdata` | postmarketOS for `qcom-sm7150` (boot partition with systemd-boot, kernel and initramfs; root partition) with the `astraos` package |
| `vbmeta.img` | `vbmeta` | empty, verification disabled |

The flash scripts also **erase** `dtbo`: the stock overlays target the
downstream kernel, and the bootloader goes straight back to fastboot when an
overlay table has no entry for the board.

## Credits

astraOS on this phone exists thanks to the **postmarketOS (Nura) team and
community**: their kernel for SM7150 phones (`linux-postmarketos-qcom-sm7150`),
device support (`device-qcom-sm7150`, `firmware-xiaomi-sweet`), initramfs
(`postmarketos-mkinitfs`), `boot-deploy`, `pmbootstrap` and the rest of the
base system. Thanks as well to the [sm7150-mainline](https://github.com/sm7150-mainline)
contributors (mainline Linux, U-Boot and firmware for these phones), and to
[Alpine Linux](https://alpinelinux.org), which postmarketOS is built on.

- postmarketOS / Nura: https://nura.eco
- pmaports (packages and device support): https://gitlab.nura.eco/nura/pmaports
- pmbootstrap: https://gitlab.nura.eco/nura/pmbootstrap

## Requirements

- An **unlocked bootloader** (Xiaomi unlock tool).
- To build: Linux or WSL2 with `sudo`, `git`, `python3`, `openssl`, `zip`,
  `kpartx`, `losetup`; on x86_64 also `qemu-user-static` + `binfmt-support`
  (the astraOS steps run in an Alpine aarch64 chroot). Docker can replace
  the chroot (`--docker`). GitHub Actions builds it on native arm64 runners
  (`.github/workflows/build.yml`).
- About 20 GB of free disk space, on a Linux filesystem (in WSL: not
  `/mnt/c`).

## Build

Clone this repository next to the `astra` repository (it is picked up
automatically; otherwise it is cloned from `ASTRA_REPO`):

```
astraos/
├── astra/
└── astra_device_xiaomi_sweet/
```

Run as your user (it asks for `sudo` when needed):

```bash
./build.sh
```

The zip lands in `out/astraOS-<version>-sweet.zip`. Steps can be run one at
a time: `./build.sh fetch uboot astra llama pmos package`.

## What the build does

1. **fetch** – the astraOS sources.
2. **uboot** – [tsryzenstech/u-boot](https://github.com/tsryzenstech/u-boot/tree/astra)
   (branch `astra`) built with `astra.config` for `sm7150-xiaomi-sweet`, wrapped
   for the stock bootloader (`u-boot.img`).
3. **astra** – astraOS for aarch64/musl, against Alpine `v3.24`, the release
   postmarketOS `v26.06` is based on, so astraOS uses the same Qt 6 and Mesa
   the phone runs.
4. **llama** – llama.cpp's server for Cloudy, the on-device assistant.
5. **pmos** – with [pmbootstrap](https://gitlab.nura.eco/nura/pmbootstrap)
   (`PMB_REF`): postmarketOS `PMOS_CHANNEL` for `qcom-sm7150`, UI `none`,
   OpenRC, no SSH server, plus the `astraos` package
   ([`pmos/astraos`](pmos/astraos)): astraOS's `/system` tree, `/vendor`
   ([`rootdir/vendor`](rootdir/vendor)), the OpenRC service, udev rules and
   kernel command line, with the dependencies in
   [`pmos/depends.txt`](pmos/depends.txt). pmbootstrap keeps its files in
   `~/.local/share/astra-pmbootstrap` (`PMB_HOME`).
6. **package** – zip with the images and the flashing scripts.

Steps 1–4 run in the Alpine aarch64 chroot of
[`scripts/chroot.sh`](scripts/chroot.sh) (made, or made again for a new
Alpine release, automatically) or in Docker with `--docker`; 5–6 run as your
user, since pmbootstrap refuses to run as root.

### How the phone boots

The stock bootloader starts **U-Boot** from `boot`. U-Boot shows nothing: it
maps `userdata` as a disk and starts postmarketOS's systemd-boot from the boot
partition of `userdata.img`, which starts postmarketOS's kernel and
initramfs. On the first boot the initramfs grows the root partition to the
whole of `userdata`.

postmarketOS's init (OpenRC) then starts its services (udev, D-Bus, iwd,
BlueZ, ModemManager, the Qualcomm modem helpers) and `astraos`: astraOS's
init as a service supervisor (`init --supervisor`), which starts astrad and
SysBoard. SysBoard shows the boot logo while the shell loads.

The boot shows no text: `console=null` (`KERNEL_CMDLINE` in
[`board.conf`](board.conf)) is added to postmarketOS's command line, and no
login prompt is shown. Every kernel message still goes to the boot log kept
in RAM (ramoops, with `ignore_loglevel`): hold **Volume Down** while the
phone starts for U-Boot's boot menu (also shown when a boot fails), and
**Show the last boot log** shows the previous boot's.

## Flash

Boot the phone into fastboot (Volume down + Power), connect it and run from
the extracted package:

```bash
./flash-all.sh
```

On Windows use `flash-all.bat`. They flash `vbmeta.img`, erase `dtbo`, flash
`u-boot.img` to `boot` and `userdata.img` to `userdata`. **This erases
everything on the phone**: as on postmarketOS, the system and your data
live together in `userdata`.

To go back to MIUI/HyperOS, flash a stock fastboot ROM with Xiaomi's tool.

### If it does not boot

- Hold **Volume Down** while the phone starts, then **Show the last boot
  log** in U-Boot's menu: the kernel log of the boot that failed. A photo of
  its last lines tells where it stopped.
- astraOS's own log is `/var/log/astraos.log` on the phone.

## Device notes

| | |
|---|---|
| SoC | Qualcomm SM7150-AC (Snapdragon 732G), Adreno 618 |
| Display | 1080 × 2400 AMOLED, command mode (`samsung,ams667yr01`), UI scale 2.75 |
| Touch | Goodix GT9896 |
| postmarketOS device | `qcom-sm7150` (community), firmware `firmware-xiaomi-sweet` |
| Boot chain | stock ABL → U-Boot (`u-boot.img`, header v0) → systemd-boot → postmarketOS kernel + initramfs → OpenRC → astraOS |

## Layout of this repository

```
board.conf            device parameters (postmarketOS release, U-Boot, kernel command line)
pmos/astraos/         the astraos postmarketOS package (APKBUILD, OpenRC service, udev rules)
pmos/depends.txt      packages astraOS needs on top of postmarketOS
rootdir/vendor/       /vendor: device boot actions (init/sweet.rc)
scripts/              build steps
flash/                fastboot flashing scripts shipped in the package
Dockerfile            build environment for the astraOS steps (Alpine aarch64)
```

## License

Build scripts and configuration: [Apache License 2.0](LICENSE).
postmarketOS, Alpine packages and firmware keep their own licenses.
