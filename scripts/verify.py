#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Stops the build when the images are not what this repository describes.

Checks everything that can be checked without the phone: the pinned kernel,
bootloader, firmware and packages, that every program finds its libraries and
every QML import its module, and that the images hold what the boot chain
reads. Writes the report to out/verify.txt; scripts/package.sh refuses images
without a passing one.

A passing report says the files are right, not that the phone shows anything:
only booting it can tell.

Run by scripts/verify.sh, which exports the paths and board.conf values.
"""
import hashlib
import os
import re
import shutil
import stat
import struct
import subprocess
import sys
import tempfile
import zlib
from pathlib import Path

import acffix
import dtbfix

env = os.environ
OUT = Path(env["OUT"])
SYSTEM = Path(env["SYSTEM_ROOT"])
VENDOR = Path(env["VENDOR_ROOT"])
RAMDISK = Path(env["RAMDISK"])
IMAGES = Path(env["IMAGES"])
DEVICE = Path(env["DEVICE_DIR"])
LIB = SYSTEM / "system/lib"
QML = LIB / "qt6/qml"

failures, warnings, report = [], [], []


def ok(what):
    report.append("ok    " + what)


def fail(what):
    failures.append(what)
    report.append("FAIL  " + what)
    if env.get("GITHUB_ACTIONS"):
        print("::error::verify: " + what)


def warn(what):
    warnings.append(what)
    report.append("warn  " + what)


def check(condition, what, why=""):
    if condition:
        ok(what)
    else:
        fail(what + (": " + why if why else ""))


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def run(*cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, errors="replace", **kw)


def readelf(path, what):
    return run("readelf", "-W", what, str(path)).stdout


class LinkLoop(Exception):
    pass


def on_phone(path):
    """What a path of /system leads to on the phone, or None.

    Absolute links start at the image's root, not at the build machine's.
    """
    parts = list(Path(path).relative_to(SYSTEM).parts)
    current, hops = SYSTEM, 0
    while parts:
        part = parts.pop(0)
        if part == "..":
            current = current.parent if current != SYSTEM else SYSTEM
            continue
        next_path = current / part
        if not next_path.is_symlink():
            current = next_path
            continue
        hops += 1
        if hops > 40:
            raise LinkLoop(str(path))
        target = os.readlink(next_path)
        if target.startswith("/"):
            current = SYSTEM
        parts[:0] = [p for p in target.split("/") if p and p != "."]
    return current if os.path.lexists(current) else None


def in_image(path):
    try:
        return on_phone(path) is not None
    except LinkLoop:
        return False


# ---- Pinned inputs ----------------------------------------------------------

def check_pins():
    if env["KERNEL_SOURCE"] == "prebuilt":
        pkg = DEVICE / env["KERNEL_PACKAGE"]
        check(pkg.is_file() and sha256(pkg) == env["KERNEL_PACKAGE_SHA256"], "kernel package checksum")
    else:
        warn("kernel built from source, not the pinned package")
    release = OUT / "kernel/include/config/kernel.release"
    got = release.read_text().strip() if release.exists() else "none"
    check(got == env["KERNEL_RELEASE"], "kernel release " + env["KERNEL_RELEASE"], "found " + got)
    check((LIB / "modules" / got / "modules.dep").is_file(), "kernel modules and modules.dep in /system/lib/modules")

    for name, src, want in (("U-Boot", "u-boot", "UBOOT_REF"), ("firmware", "firmware", "FIRMWARE_REF")):
        got = run("git", "-C", str(Path(env["SRC"]) / src), "rev-parse", "HEAD").stdout.strip()
        check(got == env[want], "%s at %s" % (name, env[want][:12]), "found " + (got[:12] or "nothing"))


def installed(db):
    pkgs, name = {}, None
    for line in db.read_text().splitlines():
        if line.startswith("P:"):
            name = line[2:]
        elif line.startswith("V:"):
            pkgs[name] = line[2:]
    return pkgs


def check_packages():
    repositories = (Path(env["STAGE"]) / "etc/apk/repositories").read_text()
    check("/%s/main" % env["ALPINE_BRANCH"] in repositories, "packages from Alpine " + env["ALPINE_BRANCH"], repositories)

    have = installed(Path(env["STAGE"]) / "lib/apk/db/installed")
    critical, drift, extra = 0, [], 0
    for line in (DEVICE / "packages.lock").read_text().splitlines():
        if line.startswith("#") or not line.strip():
            continue
        spec, *mark = line.split()
        name, want = spec.split("=", 1)
        got = have.get(name)
        if mark:
            critical += 1
            if got != want:
                fail("%s must be %s, found %s" % (name, want, got))
        elif got != want:
            drift.append("%s %s -> %s" % (name, want, got))
    ok("%d critical packages at the tested versions" % critical)
    if drift:
        warn("not critical, differ from packages.lock: " + ", ".join(drift))

    # astraOS links Qt's private APIs: built against exactly the shipped Qt.
    local = Path("/lib/apk/db/installed")
    if local.exists():
        here = installed(local)
        for name in ("qt6-qtbase", "qt6-qtdeclarative", "qt6-qtwayland"):
            check(here.get(name) == have.get(name), name + " is the same in the build environment and the image",
                  "%s here, %s in the image" % (here.get(name), have.get(name)))


# ---- /system ----------------------------------------------------------------

def check_layout():
    for link, target in (("bin", "system/bin"), ("lib", "system/lib"), ("usr", "system"), ("etc", "system/etc"),
                         ("sbin", "system/bin"), ("var", "data/var"), ("sdcard", "data/media/0"),
                         ("init", "system/bin/init")):
        path = SYSTEM / link
        check(path.is_symlink() and os.readlink(path) == target, "/%s -> %s" % (link, target))
    for d in ("dev", "proc", "sys", "run", "tmp", "mnt", "data", "vendor", "product"):
        check((SYSTEM / d).is_dir(), "mount point /" + d)

    init = SYSTEM / "system/bin/init"
    check(init.is_file() and not init.is_symlink(), "/system/bin/init is a file, not BusyBox's link")
    check("Requesting program interpreter" not in readelf(init, "-l"), "/system/bin/init is static")
    check(sha256(RAMDISK / "init") == sha256(init), "the ramdisk's /init is /system/bin/init")

    # Without these the graphics stack does not start; versions from packages.lock.
    for rel in ("ld-musl-aarch64.so.1", "libgallium-25.1.9.so", "libQt6Core.so.6.8.3", "libQt6Quick.so.6.8.3",
                "libQt6WaylandCompositor.so.6.8.3", "libEGL.so.1", "libGLESv2.so.2", "libgbm.so.1", "libdrm.so.2",
                "dri/msm_dri.so", "gbm/dri_gbm.so",
                "qt6/plugins/platforms/libqeglfs.so",
                "qt6/plugins/platforms/libqoffscreen.so",
                "qt6/plugins/egldeviceintegrations/libqeglfs-kms-integration.so",
                "qt6/libexec/QtWebEngineProcess"):
        check(in_image(LIB / rel), "/system/lib/" + rel)
    for rel in ("bin/sysboard", "bin/astrad", "bin/bootanim", "bin/udevd", "bin/udevadm", "build.prop",
                "etc/init/init.rc", "etc/init/sysboard.rc", "etc/init/astrad.rc", "etc/init/bootanim.rc",
                "etc/passwd", "etc/group"):
        check(in_image(SYSTEM / "system" / rel), "/system/" + rel)
    # Never run on the phone with this system (udevadm was a link to itself).
    rc = (SYSTEM / "system/etc/init/init.rc").read_text()
    # The bootloader leaves the hardware watchdog running: without its driver,
    # loaded by this, the phone freezes at ~30 s and resets at ~50 s.
    check("udevadm trigger --action=add" in rc, "init.rc loads the drivers of every device",
          "astra is older than this repository expects")
    # The order is what makes the panel light up without freezing the phone.
    check("trigger hardware-init" in rc and rc.index("trigger hardware-init") < rc.index("udevadm trigger --action=add"),
          "the panel is set up before all the drivers load", "astra is older than this repository expects")
    sweet = (VENDOR / "etc/init/sweet.rc").read_text()
    steps = ("modprobe qcom_wdt", "disptest reinit", "disptest setreg 0xae942a0 0x021c0b41 0x04380b01", "start bootanim")
    check("on hardware-init" in sweet and all(s in sweet for s in steps) and
          [sweet.index(s) for s in steps] == sorted(sweet.index(s) for s in steps),
          "sweet.rc: watchdog driver, panel again, two DSC slices per packet, logo")
    fonts = SYSTEM / "system/share/fonts"
    files = [f.name for f in fonts.rglob("*") if f.is_file()] if fonts.is_dir() else []
    for name, script in (("CJK", "Chinese, Japanese, Korean"), ("Arabic", "Arabic")):
        check(any(name in f for f in files), "a font for %s" % script)
    check("/system/share/fonts" in (SYSTEM / "system/etc/fonts/fonts.conf").read_text(), "fontconfig looks in /system/share/fonts")
    check((LIB / "modules" / env["KERNEL_RELEASE"] / "kernel/drivers/watchdog").is_dir() and
          any((LIB / "modules" / env["KERNEL_RELEASE"] / "kernel/drivers/watchdog").glob("qcom-wdt.ko*")),
          "the hardware watchdog's driver is in the image")
    for tool in ("rmtfs", "tqftpserv"):
        check(in_image(SYSTEM / "system/bin" / tool), "/system/bin/%s, for the modem and Wi-Fi" % tool)
    check(in_image(SYSTEM / "system/media/bootanimation/logo.png"), "the boot logo is in the image")
    # The modem: ModemManager refuses every call while PolicyKit does not answer,
    # and PolicyKit does not start without its user.
    passwd = (SYSTEM / "system/etc/passwd").read_text()
    if in_image(SYSTEM / "system/bin/ModemManager") and in_image(LIB / "polkit-1/polkitd"):
        check(any(line.startswith("polkitd:") for line in passwd.splitlines()) and "launch.sh polkitd" in (SYSTEM / "system/etc/init/connectivity.rc").read_text(),
              "PolicyKit has its user and its service (the modem's calls)", "astra is older than this repository expects")
    # NFC: the controller's driver, which the kernel's own NFC support reads tags with.
    modules = LIB / "modules" / env["KERNEL_RELEASE"] / "kernel"
    check(any(modules.glob("drivers/nfc/nxp-nci/nxp-nci_i2c.ko*")) and any(modules.glob("net/nfc/nfc.ko*")),
          "the NFC controller's driver is in the image")
    script = SYSTEM / "system/bin/astra-diag"
    check(in_image(SYSTEM / "system/bin/disptest") and script.is_file() and os.access(script, os.X_OK) and
          b"\r" not in script.read_bytes() and in_image(SYSTEM / "system/etc/init/diag.rc"), "the diagnostics are in the image")
    for d in ("app", "priv-app"):
        n = sum(1 for _ in (SYSTEM / "system" / d).iterdir()) if (SYSTEM / "system" / d).is_dir() else 0
        check(n > 0, "/system/%s has %d apps" % (d, n))


def check_links():
    """No link in /system leads back to itself; broken ones are reported."""
    count, loops, broken = 0, [], []
    for root, dirs, files in os.walk(SYSTEM / "system"):
        for name in dirs + files:
            path = Path(root) / name
            if not path.is_symlink():
                continue
            count += 1
            rel = "/" + str(path.relative_to(SYSTEM))
            try:
                if on_phone(path) is None:
                    target = os.readlink(path)
                    # Made at runtime.
                    if not target.startswith(("/run/", "/proc/", "/dev/", "/tmp/", "/data/")):
                        broken.append("%s -> %s" % (rel, target))
            except LinkLoop:
                loops.append("%s -> %s" % (rel, os.readlink(path)))
    check(not loops, "none of the %d links in /system leads back to itself" % count, ", ".join(loops[:30]))
    if broken:
        warn("%d broken links: %s" % (len(broken), ", ".join(broken[:15])))


def is_elf(path):
    try:
        with open(path, "rb") as f:
            return f.read(4) == b"\x7fELF"
    except OSError:
        return False


def resolve_runpath(value, elf):
    """RUNPATH directories on the phone, as paths in the tree being built."""
    dirs = []
    for d in value.split(":"):
        d = d.replace("$ORIGIN", "/" + str(elf.parent.relative_to(SYSTEM))).replace("${ORIGIN}", "/" + str(elf.parent.relative_to(SYSTEM)))
        d = os.path.normpath(d).lstrip("/")
        for prefix, real in (("usr/", "system/"), ("lib", "system/lib"), ("bin", "system/bin")):
            if d == prefix.rstrip("/") or d.startswith(prefix):
                d = real + d[len(prefix):]
                break
        dirs.append(SYSTEM / d)
    return dirs


def check_elfs():
    """Every program and library: aarch64, and all NEEDED found where musl looks."""
    skip = (LIB / "firmware", LIB / "modules", SYSTEM / "system/share")
    default = [LIB, SYSTEM / "system/local/lib"]
    count, wrong, missing = 0, [], []
    for root, dirs, files in os.walk(SYSTEM / "system"):
        root = Path(root)
        if root in skip:
            dirs[:] = []
            continue
        for name in files:
            path = root / name
            if path.is_symlink() or not is_elf(path) or path.suffix in (".o", ".a", ".ko"):
                continue
            count += 1
            rel = "/" + str(path.relative_to(SYSTEM))
            machine = readelf(path, "-h")
            if "AArch64" not in machine:
                wrong.append(rel)
                continue
            dynamic = readelf(path, "-d")
            search = list(default)
            for m in re.finditer(r"\((?:RUNPATH|RPATH)\)\s+Library r(?:un)?path: \[(.*?)\]", dynamic):
                search += resolve_runpath(m.group(1), path)
            for need in re.findall(r"\(NEEDED\)\s+Shared library: \[(.*?)\]", dynamic):
                if not any(in_image(d / need) for d in search):
                    missing.append("%s needs %s" % (rel, need))
    check(not wrong, "%d programs and libraries are all aarch64" % count, ", ".join(wrong[:20]))
    check(not missing, "every library they need is in the image",
          "; ".join(missing[:30]) + (" (and %d more)" % (len(missing) - 30) if len(missing) > 30 else ""))


def check_qml_imports():
    """Every module astraOS's QML imports exists on the phone."""
    src = Path(env["ASTRA_SOURCE"])
    own = set()
    for cmake in src.rglob("CMakeLists.txt"):
        own.update(re.findall(r"\bURI\s+\"?([\w.]+)", cmake.read_text(errors="replace")))
    framework = SYSTEM / "system/framework/qml"
    missing, modules = {}, set()
    pattern = re.compile(r"^\s*import\s+([A-Za-z_][\w.]*)", re.M)
    for qml in src.rglob("*.qml"):
        parts = qml.relative_to(src).parts
        if parts[0] in ("out", "build", "sdk", "tests", "docs", "tools") or "templates" in parts:
            continue
        for module in pattern.findall(qml.read_text(errors="replace")):
            path = module.replace(".", "/")
            if module in own or (QML / path / "qmldir").exists() or (framework / path / "qmldir").exists():
                modules.add(module)
            else:
                missing.setdefault(module, str(qml.relative_to(src)))
    check(not missing, "%d QML modules imported by astraOS are all in the image" % len(modules),
          "; ".join("%s (%s)" % kv for kv in missing.items()))


def check_rc():
    init = OUT / "astra-install/system/bin/init"
    for rcdir, services in ((SYSTEM / "system/etc/init", ("ueventd", "bootanim", "sysboard", "astrad")),
                            (VENDOR / "etc/init", ())):
        try:
            result = run(str(init), "--check", str(rcdir), timeout=60)
        except OSError as e:
            warn("cannot run init here (%s): .rc files not checked" % e)
            return
        dump = result.stdout + result.stderr
        check(result.returncode == 0, "init parses " + str(rcdir.relative_to(OUT)))
        for service in services:
            check(service in dump, "init knows the service " + service)
        if services:
            check("astra-diag" in dump and "on diag" in dump, "init knows the diagnostics")
        for line in dump.splitlines():
            if re.search(r"\b(error|unknown|invalid|bad)\b", line, re.I):
                fail("init on %s: %s" % (rcdir.name, line))


def check_firmware():
    for rel in ("qcom/a630_sqe.fw", "qcom/a630_gmu.bin"):
        found = list((RAMDISK / "lib/firmware").glob(rel + "*"))
        check(bool(found), "GPU firmware /lib/firmware/%s in the ramdisk" % rel)
    zap = "qcom/sm7150/xiaomi/sweet/a615_zap.mbn"
    check((RAMDISK / "lib/firmware" / zap).is_file(), "GPU zap shader in the ramdisk")
    check((VENDOR / "firmware" / zap).is_file(), "GPU zap shader in /vendor/firmware")
    acf = VENDOR / "firmware/aw88261_acf.bin"
    # The downloaded file (fetch.sh checks AW_ACF_SHA256) as acffix.py corrects it.
    check(acf.is_file() and sha256(acf) == acffix.FIXED_SHA256, "the amplifiers' calibration file, corrected")
    for rel in ("conf.d/sm8250/xiaomi-XiaomiRedmiNote10Pro.conf", "Xiaomi/sweet/HiFi.conf"):
        check((SYSTEM / "system/share/alsa/ucm2" / rel).is_file(), "the speaker's ALSA profile " + rel)
    # The names the kernel asks for lead to what is on the phone (see build-rootfs.sh).
    for link, target in (("crbtfw01.tlv.zst", "crbtfw21.tlv.zst"), ("crnv01.bin.zst", "crnv21.bin.zst")):
        check(os.readlink(VENDOR / "firmware/qca" / link) == "/lib/firmware/qca/" + target
              and (SYSTEM / "system/lib/firmware/qca" / target).is_file(), "Bluetooth firmware %s" % link)
    check((RAMDISK / "bin/busybox").is_file(), "rescue shell in the ramdisk")
    check((RAMDISK / "first_stage.fstab").read_bytes() == (VENDOR / "etc/fstab").read_bytes(), "first stage fstab is /vendor/etc/fstab")
    check((VENDOR / "etc/init/sweet.rc").is_file(), "/vendor/etc/init/sweet.rc")
    prop = (VENDOR / "build.prop").read_text() if (VENDOR / "build.prop").exists() else ""
    check("ro.astra.ui.scale=" in prop, "/vendor/build.prop")
    # Updates (see astra's docs/VERSIONING.md): where they come from and what this build is.
    repo = re.search(r"^ro\.astra\.ota\.repo=([\w.-]+/[\w.-]+)$", prop, re.M)
    check(bool(repo), "updates come from %s" % (repo.group(1) if repo else "nowhere (OTA_REPOSITORY)"))
    channel = re.search(r"^ro\.astra\.ota\.channel=(stable|prerelease|local)$", prop, re.M)
    check(bool(channel) and (VENDOR / "etc/astra-release.json").is_file(),
          "update channel %s and the release notes" % (channel.group(1) if channel else "?"))
    check("ro.astra.display.refresh=120" in prop, "the display stays at 120 Hz, the only rate that shows a clean image")


# ---- Images -----------------------------------------------------------------

def in_ext4(image, paths):
    img = IMAGES / image
    if not img.is_file():
        fail(image + " missing")
        return
    for path in paths:
        out = run("debugfs", "-R", "stat " + path, str(img))
        check("File not found" not in out.stdout + out.stderr and "Inode:" in out.stdout, "%s holds %s" % (image, path))


def pe_sections(data):
    pe = struct.unpack_from("<I", data, 0x3c)[0]
    count, opt = struct.unpack_from("<HxxxxxxxxxxxxH", data, pe + 6)
    sections, off = {}, pe + 24 + opt
    for i in range(count):
        name = data[off:off + 8].rstrip(b"\0").decode(errors="replace")
        vsize, _, rawsize, rawoff = struct.unpack_from("<IIII", data, off + 8)
        sections[name] = data[rawoff:rawoff + min(vsize, rawsize)]
        off += 40
    return sections


def check_efi():
    kboot = OUT / "kernel/arch/arm64/boot"
    dtb = kboot / "dts" / env["KERNEL_DTB"]
    check(dtb.is_file() and b"xiaomi,sweet" in dtb.read_bytes(), "device tree is sweet's")
    # Without this the first touch freezes the phone: see dtbfix.py.
    tree = dtb.read_bytes()
    left, votes = dtbfix.wrong(tree), dtbfix.qup1_votes(tree)
    check(not left and votes > 0, "QUP1 and the SD card vote on the right interconnect",
          "%d wrong, %d right" % (len(left), votes))
    old, right = dtbfix.amplifiers(tree)
    check(not old and right == 2, "the amplifiers bind to their driver", "%d old, %d right" % (len(old), right))
    flash = dtbfix.flash_led(tree)
    check(bool(flash) and flash[1] == dtbfix.OKAY, "the flash LED (the torch) is on in the device tree")
    # The corrected tree, read by the device tree compiler itself.
    if shutil.which("dtc"):
        dts = subprocess.run(["dtc", "-I", "dtb", "-O", "dts", "-q", str(dtb)], capture_output=True, text=True)
        node = dts.stdout.partition("led-controller@d300 {")[2].partition("led-1 {")[0]
        check(dts.returncode == 0 and 'status = "okay"' in node, "dtc reads the corrected device tree",
              dts.stderr.strip()[:200])
    image = (OUT / "Image").read_bytes()
    check(image[0x38:0x3c] == b"ARMd", "kernel is an arm64 Image")

    efi = OUT / "esp/EFI/BOOT/BOOTAA64.EFI"
    data = efi.read_bytes()
    sections = pe_sections(data)
    check(data[:2] == b"MZ" and ".linux" in sections, "BOOTAA64.EFI is a unified kernel image")
    cmdline = sections.get(".cmdline", b"").rstrip(b"\0\n").decode(errors="replace")
    check(cmdline == env["BOOT_CMDLINE"], "kernel command line of BOOTAA64.EFI", "found '%s'" % cmdline)
    check("console=null" in cmdline, "no console on the screen (console=null)")
    check(sections.get(".linux", b"").rstrip(b"\0") .startswith(image[:1 << 20]), "BOOTAA64.EFI holds this kernel")
    ramdisk = (OUT / "ramdisk.cpio.gz").read_bytes()
    check(sections.get(".initrd", b"")[:len(ramdisk)] == ramdisk, "BOOTAA64.EFI holds this ramdisk")

    # The EFI partition, read back from the image U-Boot reads.
    sector = int(env["STORAGE_SECTOR_SIZE"])
    user = (IMAGES / "userdata.img").read_bytes()
    check(user[510:512] == b"\x55\xaa" and user[sector:sector + 8] == b"EFI PART", "userdata.img has a GPT with %d byte sectors" % sector)
    header = bytearray(user[sector:sector + 92])
    crc = struct.unpack_from("<I", header, 16)[0]
    header[16:20] = b"\0\0\0\0"
    check(zlib.crc32(bytes(header)) == crc, "userdata.img GPT checksum")
    first, last = struct.unpack_from("<QQ", user, 2 * sector + 32)
    name = user[2 * sector + 56:2 * sector + 128].decode("utf-16-le", "replace").rstrip("\0")
    check(name == "astra_esp", "first partition is astra_esp", "found " + name)
    fat = user[first * sector:(last + 1) * sector]
    with tempfile.NamedTemporaryFile(dir=OUT, suffix=".fat") as tmp:
        tmp.write(fat)
        tmp.flush()
        listing = run("mdir", "-/", "-b", "-i", tmp.name, "::/").stdout.lower()
        check("efi/boot/bootaa64.efi" in listing, "the EFI partition holds \\EFI\\BOOT\\BOOTAA64.EFI")
        check(("dtb/" + env["KERNEL_DTB"]).lower() in listing, "the EFI partition holds the kernel's device tree")
        copy = run("mcopy", "-n", "-i", tmp.name, "::/EFI/BOOT/BOOTAA64.EFI", tmp.name + ".efi")
        if copy.returncode == 0:
            check(sha256(tmp.name + ".efi") == sha256(efi), "BOOTAA64.EFI in the image is the built one")
            os.unlink(tmp.name + ".efi")
    wipe = IMAGES / "userdata-wipe.img"
    check(wipe.stat().st_size == len(user) + (1 << 20), "userdata-wipe.img clears where /data starts")

    # The diagnostic image: the same kernel and ramdisk, only one word more.
    diag = pe_sections((OUT / "esp-diag/EFI/BOOT/BOOTAA64.EFI").read_bytes())
    line = diag.get(".cmdline", b"").rstrip(b"\0\n").decode(errors="replace")
    check(line == env["BOOT_CMDLINE"] + " astra.diag", "the diagnostic image adds only astra.diag", "found '%s'" % line)
    check("astra.diag" not in env["BOOT_CMDLINE"], "the normal image does not run the diagnostics")
    check(diag.get(".linux") == sections.get(".linux") and diag.get(".initrd") == sections.get(".initrd"),
          "the diagnostic image has the same kernel and ramdisk")
    check((IMAGES / "userdata-diag.img").stat().st_size == len(user) + (1 << 20), "userdata-diag.img clears where /data starts")


def check_images():
    for name in ("boot.img", "boot-debug.img", "boot-rescue.img"):
        with open(IMAGES / name, "rb") as f:
            head = f.read(48)
        check(head[:8] == b"ANDROID!" and struct.unpack_from("<I", head, 40)[0] == 2, name + " is a header v2 boot image")
    uboot = OUT / "u-boot/u-boot.img"
    check(uboot.is_file() and uboot.read_bytes()[:8] == b"ANDROID!", "u-boot.img is a boot image")
    if uboot.is_file():
        check(0 < uboot.stat().st_size < 8 << 20, "u-boot.img has a sensible size (%d bytes)" % uboot.stat().st_size)

    vb = (IMAGES / "vbmeta.img").read_bytes()
    check(vb[:4] == b"AVB0" and struct.unpack_from(">I", vb, 120)[0] == 3, "vbmeta.img disables verification")

    with open(IMAGES / "super.img", "rb") as f:
        check(struct.unpack("<I", f.read(4))[0] == 0xed26ff3a, "super.img is sparse")
    total = sum((IMAGES / (p + ".img")).stat().st_size for p in env["SUPER_PARTITIONS"].split())
    check(total <= int(env["SUPER_GROUP_SIZE"]), "system, vendor and product fit in super (%d MiB)" % (total >> 20))

    in_ext4("system.img", ("/system/bin/init", "/system/bin/sysboard", "/system/bin/astrad", "/system/bin/bootanim",
                           "/system/lib/libgallium-25.1.9.so", "/system/lib/libQt6Core.so.6.8.3",
                           "/system/etc/init/init.rc", "/init", "/data", "/vendor", "/product"))
    in_ext4("vendor.img", ("/etc/fstab", "/etc/init/sweet.rc", "/build.prop", "/firmware"))
    in_ext4("product.img", ("/build.prop",))


# ---- SysBoard's QML against the real Qt -------------------------------------

QML_ERROR = re.compile(r"QQmlApplicationEngine failed to load|No module named|module \".*\" is not installed|"
                       r"\.qml:\d+(:\d+)?: .*(is not a type|Cannot assign to non-existent|unavailable|"
                       r"Non-existent attached object|Invalid property assignment)")


def check_sysboard_starts():
    """Loads SysBoard's whole QML on the Qt of this build, without a display."""
    sysboard = OUT / "astra-install/system/bin/sysboard"
    if not Path("/etc/alpine-release").exists():
        warn("not in the build environment: SysBoard's QML not loaded")
        return
    root = Path(tempfile.mkdtemp(dir=OUT, prefix="verify-root"))
    try:
        (root / "system").symlink_to(OUT / "astra-install/system")
        for d in ("data/system", "dev/socket", "run/astra/display", "vendor", "product"):
            (root / d).mkdir(parents=True)
        run_env = dict(os.environ, ASTRA_ROOT=str(root), QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software",
                       XDG_RUNTIME_DIR=str(root / "run/astra/display"), QT_LOGGING_RULES="*.debug=false",
                       LD_LIBRARY_PATH=str(OUT / "astra-install/system/lib"))
        run_env.pop("QT_PLUGIN_PATH", None)
        try:
            result = subprocess.run([str(sysboard)], env=run_env, capture_output=True, timeout=60)
            log, code = result.stdout + result.stderr, result.returncode
        except subprocess.TimeoutExpired as e:
            # Still running after a minute: it loaded.
            log, code = (e.stdout or b"") + (e.stderr or b""), None
        log = log.decode(errors="replace")
        errors = [l for l in log.splitlines() if QML_ERROR.search(l)]
        (OUT / "verify-sysboard.log").write_text(log)
        check(not errors, "SysBoard's QML loads on this Qt without a display", "; ".join(errors[:10]))
        if code is not None and not errors:
            warn("SysBoard stopped by itself without a display (exit code %s): see out/verify-sysboard.log" % code)
        if "sysboard: shell ready" in log:
            ok("the shell finished loading behind the boot logo")
        else:
            warn("the shell did not finish loading in a minute without a display")
    finally:
        shutil.rmtree(root, ignore_errors=True)


def main():
    for step in (check_pins, check_packages, check_layout, check_links, check_elfs, check_qml_imports, check_rc,
                 check_firmware, check_efi, check_images, check_sysboard_starts):
        report.append("--- " + step.__name__[len("check_"):])
        try:
            step()
        except Exception as e:  # a check that cannot run is a failed check
            fail("%s could not run: %s: %s" % (step.__name__, type(e).__name__, e))
    result = "PASS" if not failures else "FAIL"
    report.append("")
    report.append("%d failures, %d warnings" % (len(failures), len(warnings)))
    report.append("RESULT: " + result)
    text = "\n".join(report) + "\n"
    (OUT / "verify.txt").write_text(text)
    sys.stdout.write(text)
    if failures:
        print("\nverify: the images were NOT packaged:", file=sys.stderr)
        for f in failures:
            print("  - " + f, file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
