@echo off
rem SPDX-License-Identifier: Apache-2.0
rem Collects the boot logs of a Redmi Note 10 Pro that does not start astraOS.
rem   1. After the failed boot hold Power + Volume down until fastboot shows.
rem   2. Connect the phone and run this file.
rem The phone starts boot-rescue.img (nothing is flashed), shows up as a USB
rem drive named ASTRALOGS, and the logs are copied to Desktop\astra-logs.
setlocal
cd /d "%~dp0"
where fastboot >nul 2>nul || (echo fastboot not found ^(install Android platform-tools^) & exit /b 1)
fastboot boot boot-rescue.img || exit /b 1
echo Waiting for the phone to show up as the ASTRALOGS drive (up to 3 minutes)...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$d = $null; for ($i = 0; $i -lt 90 -and -not $d; $i++) { Start-Sleep 2; $d = (Get-Volume -FileSystemLabel ASTRALOGS -ErrorAction SilentlyContinue | Select-Object -First 1).DriveLetter };" ^
  "if (-not $d) { Write-Host 'The phone did not show up as a USB drive.'; exit 1 };" ^
  "$dst = Join-Path ([Environment]::GetFolderPath('Desktop')) 'astra-logs'; New-Item -ItemType Directory -Force $dst | Out-Null;" ^
  "Copy-Item ($d + ':\*') $dst -Force; Write-Host ('Logs copied to ' + $dst)"
