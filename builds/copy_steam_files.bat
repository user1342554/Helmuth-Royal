@echo off
REM Steam Build Helper Script
REM Run this after exporting to copy required Steam files to the build directory

echo Copying Steam files to build directory...

REM Copy steam_api64.dll
copy /Y "..\steam_api64.dll" "." 
if errorlevel 1 (
    echo Warning: Could not copy steam_api64.dll from project root
    copy /Y "..\addons\steam_api64.dll" "."
)

REM Copy steam_appid.txt (only for development/testing - remove for release!)
copy /Y "..\steam_appid.txt" "."

echo.
echo Steam files copied successfully!
echo.
echo IMPORTANT: For Steam release builds:
echo   1. Remove steam_appid.txt from the final build folder
echo   2. Update steam_appid.txt with your actual Steam App ID
echo   3. The game should be launched through Steam for proper authentication
echo.
pause
