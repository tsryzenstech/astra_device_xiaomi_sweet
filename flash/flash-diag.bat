@echo off
rem SPDX-License-Identifier: Apache-2.0
rem Flashes the developer version of astraOS on a Redmi Note 10 Pro (sweet) in
rem fastboot mode. It erases all the data on the phone. It is the normal system,
rem with a root shell on the USB serial port and the kernel log kept in /data/diag.
setlocal
cd /d "%~dp0"

where fastboot >nul 2>nul || (echo fastboot not found ^(install Android platform-tools^) & exit /b 1)

fastboot getvar product 2>&1 | findstr /r /c:"^product: *sweet" >nul || (echo This build is for the Redmi Note 10 Pro ^(sweet^). & exit /b 1)

fastboot flash vbmeta --disable-verity --disable-verification vbmeta.img || exit /b 1
fastboot erase dtbo || exit /b 1
fastboot flash boot u-boot.img || exit /b 1
fastboot flash super super.img || exit /b 1
fastboot erase metadata
fastboot flash userdata userdata-diag.img || exit /b 1
fastboot reboot
echo.
echo Done. Leave the phone connected.
