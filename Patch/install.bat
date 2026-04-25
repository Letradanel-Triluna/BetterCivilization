@echo off
setlocal EnableDelayedExpansion

echo ============================================================
echo   BetterCivilization Patch — Auto Installer
echo ============================================================
echo.

rem ---- Find Steam path via registry ----
set "STEAM_PATH="
for /f "usebackq tokens=2*" %%a in (
  `reg query "HKCU\Software\Valve\Steam" /v "SteamPath" 2^>nul`
) do set "STEAM_PATH=%%b"

if not defined STEAM_PATH (
  for /f "usebackq tokens=2*" %%a in (
    `reg query "HKLM\SOFTWARE\WOW6432Node\Valve\Steam" /v "InstallPath" 2^>nul`
  ) do set "STEAM_PATH=%%b"
)

if not defined STEAM_PATH (
  for /f "usebackq tokens=2*" %%a in (
    `reg query "HKLM\SOFTWARE\Valve\Steam" /v "InstallPath" 2^>nul`
  ) do set "STEAM_PATH=%%b"
)

if not defined STEAM_PATH (
  echo [ERROR] Steam installation not found in registry.
  echo         Please copy the "Files" folder manually to:
  echo         ...\Steam\steamapps\common\Sid Meier's Civilization V\
  echo                  Assets\DLC\Tournament Mod V12.2a\
  goto :done
)

rem Normalise slashes
set "STEAM_PATH=%STEAM_PATH:/=\%"

set "CIV_DIR=%STEAM_PATH%\steamapps\common\Sid Meier's Civilization V"
set "MOD_DIR=%CIV_DIR%\Assets\DLC\Tournament Mod V12.2a"

echo Steam found at : %STEAM_PATH%
echo Civ5 folder    : %CIV_DIR%
echo Mod folder     : %MOD_DIR%
echo.

rem ---- Verify Civ5 is installed at expected path ----
if not exist "%CIV_DIR%\" (
  echo [ERROR] Civ5 folder not found:
  echo         %CIV_DIR%
  echo.
  echo         If Civ5 is on a different drive, edit this script and set
  echo         CIV_DIR manually near the top.
  goto :done
)

rem ---- Verify Tournament Mod is installed ----
if not exist "%MOD_DIR%\" (
  echo [ERROR] Tournament Mod V12.2a folder not found:
  echo         %MOD_DIR%
  echo.
  echo         Please install Tournament Mod V12.2a first, then re-run.
  goto :done
)

rem ---- Copy files ----
echo Copying patch files...
echo.

set "SRC=%~dp0Files"

xcopy /Y /I /Q "%SRC%\CvGameCore_Expansion2.dll" "%MOD_DIR%\"
if errorlevel 1 goto :copy_error

xcopy /Y /I /Q "%SRC%\Override\CIV5Units.xml" "%MOD_DIR%\Override\"
if errorlevel 1 goto :copy_error

xcopy /Y /I /Q "%SRC%\Override\CIV5Units_Mongol.xml" "%MOD_DIR%\Override\"
if errorlevel 1 goto :copy_error

xcopy /Y /I /Q "%SRC%\Override\CIV5UnitPromotions_Expansion2.xml" "%MOD_DIR%\Override\"
if errorlevel 1 goto :copy_error

echo.
echo ============================================================
echo   Done! Launch Civilization V and load Tournament Mod.
echo ============================================================
goto :done

:copy_error
echo.
echo [ERROR] A file could not be copied. Check that Civ5 is closed
echo         and that you have write permission to the folder above.

:done
echo.
pause
endlocal
