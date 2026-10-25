@echo off
rem Drag a mod folder (or a folder of mods / .tar.xz files) onto this file to install the newest build of each.
set TOOL=%~dp0mods\_build\modtool.py
where py >nul 2>nul
if %errorlevel%==0 (py -3 "%TOOL%" install "%~1") else (python "%TOOL%" install "%~1")
echo.
pause
