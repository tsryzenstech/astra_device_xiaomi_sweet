@echo off
rem SPDX-License-Identifier: Apache-2.0
rem Flashes astraOS on a Xiaomi Redmi Note 10 Pro (sweet) in fastboot mode.
rem   flash-all.bat          update an existing astraOS install (keeps /data)
rem   flash-all.bat --wipe   first install: also erases userdata (ALL your data)
rem With u-boot.img (sm7150-mainline's U-Boot for sweet) next to this file,
rem U-Boot goes to boot and starts astraOS from userdata.img (the start of
rem userdata); without it, boot.img is started by the stock bootloader.
setlocal
cd /d "%~dp0"

where fastboot >nul 2>nul || (echo fastboot not found ^(install Android platform-tools^) & exit /b 1)

fastboot getvar product 2>&1 | findstr /r /c:"^product: *sweet" >nul || (echo This build is for the Redmi Note 10 Pro ^(sweet^). & exit /b 1)

fastboot flash vbmeta --disable-verity --disable-verification vbmeta.img || exit /b 1
rem The stock overlays do not fit the mainline device tree: erase them.
fastboot erase dtbo || exit /b 1
if exist u-boot.img (
    echo Flashing U-Boot to boot...
    fastboot flash boot u-boot.img || exit /b 1
) else (
    fastboot flash boot boot.img || exit /b 1
)
fastboot flash super super.img || exit /b 1

if "%~1"=="--wipe" (
    echo Erasing userdata and metadata...
    fastboot erase metadata
    fastboot erase userdata
)
if exist u-boot.img (
    echo Flashing the EFI partition at the start of userdata...
    fastboot flash userdata userdata.img || exit /b 1
)

fastboot reboot
echo Done. The first boot formats /data and can take a little longer.
