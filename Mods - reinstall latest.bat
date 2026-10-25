@echo off
rem Uninstall every mod (except language packs) and install the v1 set (LDK x3).
set TOOL=%~dp0mods\_build\modtool.py
set V1=%~dp0release\v1
where py >nul 2>nul
if %errorlevel%==0 (py -3 "%TOOL%" refresh "%V1%") else (python "%TOOL%" refresh "%V1%")
echo.
pause
