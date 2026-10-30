@echo off
rem SPDX-License-Identifier: Apache-2.0
rem Flashes astraOS on a Xiaomi Redmi Note 10 Pro (sweet) in fastboot mode.
rem The bootloader must be unlocked.
rem As postmarketOS installs on this phone: U-Boot goes to boot, and the whole
rem system (postmarketOS with astraOS) to userdata. This ERASES EVERYTHING on
rem the phone, user data included.
setlocal
cd /d "%~dp0"

where fastboot >nul 2>nul || (echo fastboot not found ^(install Android platform-tools^) & exit /b 1)

fastboot getvar product 2>&1 | findstr /r /c:"^product: *sweet" >nul || (echo This build is for the Redmi Note 10 Pro ^(sweet^). & exit /b 1)

fastboot flash vbmeta --disable-verity --disable-verification vbmeta.img || exit /b 1
rem The stock overlays do not fit the mainline device tree: erase them.
fastboot erase dtbo || exit /b 1
echo Flashing U-Boot to boot...
fastboot flash boot u-boot.img || exit /b 1
echo Flashing the system to userdata (this takes a few minutes)...
fastboot flash userdata userdata.img || exit /b 1

fastboot reboot
echo Done. The first boot grows the system to the whole userdata partition.
