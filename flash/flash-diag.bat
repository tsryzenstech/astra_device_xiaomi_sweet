@echo off
rem SPDX-License-Identifier: Apache-2.0
rem Flashes the diagnostic version of astraOS on a Redmi Note 10 Pro (sweet) in
rem fastboot mode. It erases all the data on the phone. Leave the phone connected:
rem it tests the display by itself and shows the results as a USB drive, ASTRADIAG.
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
echo Done. Leave the phone connected and on: the tests take about 10 minutes and the
echo screen may stay black or restart. There is nothing else to do on the phone.
