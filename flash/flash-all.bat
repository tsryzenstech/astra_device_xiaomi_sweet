@echo off
rem SPDX-License-Identifier: Apache-2.0
rem Flashes astraOS on a Xiaomi Redmi Note 10 Pro (sweet) in fastboot mode.
rem   flash-all.bat          update an existing astraOS install (keeps /data)
rem   flash-all.bat --wipe   first install: also erases userdata (ALL your data)
rem   --stock-boot           start boot.img from the stock bootloader instead of U-Boot
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
set uboot=0
if exist u-boot.img set uboot=1
if "%~1"=="--stock-boot" set uboot=0
if "%~2"=="--stock-boot" set uboot=0
if "%uboot%"=="1" (
    echo Flashing U-Boot to boot...
    fastboot flash boot u-boot.img || exit /b 1
) else (
    fastboot flash boot boot.img || exit /b 1
)
fastboot flash super super.img || exit /b 1

set wipe=0
if "%~1"=="--wipe" set wipe=1
if "%~2"=="--wipe" set wipe=1
rem With U-Boot, userdata starts with the EFI partition. --wipe flashes the
rem version that also clears where /data starts (the phone formats it on the
rem first boot): erasing the whole partition takes longer than USB waits.
if "%uboot%"=="1" (
    if "%wipe%"=="1" (
        echo Erasing metadata, flashing the EFI partition and clearing /data...
        fastboot erase metadata
        fastboot flash userdata userdata-wipe.img || exit /b 1
    ) else (
        echo Flashing the EFI partition at the start of userdata...
        fastboot flash userdata userdata.img || exit /b 1
    )
) else (
    if "%wipe%"=="1" (
        echo Erasing userdata and metadata...
        fastboot erase metadata
        fastboot erase userdata
    )
)

fastboot reboot
echo Done. The first boot formats /data and can take a little longer.
