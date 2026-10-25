@echo off
rem Reinstall every MKSMK mod, choosing the Legendary Dark Knight and Shaolin Shuffle levels.
rem Close the launcher and the game first.
set TOOL=%~dp0mods\_build\modtool.py
choice /c 234 /n /m "Legendary Dark Knight: x2, x3 or x4? [2/3/4] "
if errorlevel 3 (set LDK=x4) else if errorlevel 2 (set LDK=x3) else (set LDK=x2)
choice /c nwc /n /m "Shaolin Shuffle: Normal, Wild or Chaos? [N/W/C] "
if errorlevel 3 (set SHUFFLE=chaos) else if errorlevel 2 (set SHUFFLE=wild) else (set SHUFFLE=normal)
choice /c yn /n /m "Include the MKSMK Probe (diagnostics)? [Y/N] "
if errorlevel 2 (set PROBE=) else (set PROBE=--with-probe)
echo.
echo Installing: LDK %LDK%, Shuffle %SHUFFLE% %PROBE%
where py >nul 2>nul
if %errorlevel%==0 (py -3 "%TOOL%" refresh %PROBE% --ldk %LDK% --shuffle %SHUFFLE%) else (python "%TOOL%" refresh %PROBE% --ldk %LDK% --shuffle %SHUFFLE%)
echo.
pause
