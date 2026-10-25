@echo off
rem Uninstall every mod except language packs. Removed files go to mods\.mksmk-backup.
set TOOL=%~dp0mods\_build\modtool.py
where py >nul 2>nul
if %errorlevel%==0 (py -3 "%TOOL%" uninstall-all) else (python "%TOOL%" uninstall-all)
echo.
pause
