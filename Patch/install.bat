@echo off
setlocal EnableDelayedExpansion

echo ============================================================
echo   BetterCivilization Patch — Auto Installer
echo ============================================================
echo.

rem ---- Find Steam installation path via registry ----
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

rem ---- Scan all Steam library folders for Civ5 ----
set "CIV_COUNT=0"

rem libraryfolders.vdf lists all libraries including the default one
set "VDF=%STEAM_PATH%\config\libraryfolders.vdf"
if not exist "%VDF%" set "VDF=%STEAM_PATH%\steamapps\libraryfolders.vdf"

if exist "%VDF%" (
  rem Each "path" line looks like:  [tabs]"path"[tabs]"D:\\SteamLibrary"
  rem tokens=4 with delimiter " extracts the 4th quoted segment = the path value
  for /f "usebackq tokens=4 delims=""" %%P in (`findstr /i "\"path\"" "%VDF%"`) do (
    set "LIBPATH=%%P"
    set "LIBPATH=!LIBPATH:/=\!"
    call :check_library "!LIBPATH!"
  )
) else (
  rem Fallback: only check the default Steam library
  call :check_library "%STEAM_PATH%"
)

rem ---- Handle results ----
if %CIV_COUNT%==0 (
  echo [ERROR] Civilization V was not found in any Steam library.
  echo.
  echo   Make sure Civ5 is installed via Steam, then re-run.
  goto :done
)

if %CIV_COUNT%==1 (
  rem Only one installation found — use it automatically
  set "CIV_DIR=!CIV_1!"
  goto :install
)

rem ---- Multiple installations found — ask user to choose ----
echo Found Civilization V in %CIV_COUNT% locations:
echo.
for /l %%i in (1,1,%CIV_COUNT%) do (
  echo   [%%i] !CIV_%%i!
)
echo.

:ask_choice
set /p "CHOICE=Enter the number of your Civ5 installation [1-%CIV_COUNT%]: "

set "CIV_DIR="
for /l %%i in (1,1,%CIV_COUNT%) do (
  if "!CHOICE!"=="%%i" set "CIV_DIR=!CIV_%%i!"
)

if not defined CIV_DIR (
  echo   Invalid choice, please try again.
  goto :ask_choice
)

:install
set "MOD_DIR=%CIV_DIR%\Assets\DLC\Tournament Mod V12.2a"

echo.
echo Civ5 folder : %CIV_DIR%
echo Mod folder  : %MOD_DIR%
echo.

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

rem ================================================================
:check_library
rem  Checks if the given Steam library path contains Civ5.
rem  If found, appends it to the CIV_x list.
set "CHECK=%~1\steamapps\common\Sid Meier's Civilization V"
if exist "%CHECK%\" (
  set /a CIV_COUNT+=1
  set "CIV_!CIV_COUNT!=%CHECK%"
)
exit /b

rem ================================================================
:copy_error
echo.
echo [ERROR] A file could not be copied. Check that Civ5 is closed
echo         and that you have write permission to the folder above.

:done
echo.
pause
endlocal
