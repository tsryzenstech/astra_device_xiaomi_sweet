@echo off
rem SPDX-License-Identifier: Apache-2.0
rem Flashes astraOS on a Xiaomi Redmi Note 10 Pro (sweet) in fastboot mode.
rem   flash-all.bat          update an existing astraOS install (keeps /data)
rem   flash-all.bat --wipe   first install: also erases userdata (ALL your data)
setlocal
cd /d "%~dp0"

where fastboot >nul 2>nul || (echo fastboot not found ^(install Android platform-tools^) & exit /b 1)

fastboot getvar product 2>&1 | findstr /r /c:"^product: *sweet" >nul || (echo This build is for the Redmi Note 10 Pro ^(sweet^). & exit /b 1)

fastboot flash vbmeta --disable-verity --disable-verification vbmeta.img || exit /b 1
fastboot flash dtbo dtbo.img || exit /b 1
fastboot flash boot boot.img || exit /b 1
fastboot flash super super.img || exit /b 1

if "%~1"=="--wipe" (
    echo Erasing userdata and metadata...
    fastboot erase metadata
    fastboot erase userdata
)

fastboot reboot
echo Done. The first boot formats /data and can take a little longer.
