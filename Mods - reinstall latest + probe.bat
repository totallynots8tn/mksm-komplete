@echo off
rem Same, plus the MKSMK Probe diagnostics (LDK x3).
set TOOL=%~dp0mods\_build\modtool.py
set V1=%~dp0release\v1
where py >nul 2>nul
if %errorlevel%==0 (py -3 "%TOOL%" refresh "%V1%" --with-probe) else (python "%TOOL%" refresh "%V1%" --with-probe)
echo.
pause
