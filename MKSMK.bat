@echo off
rem MKSM Komplete+ dev menu: every install, QA and uninstall action in one window.
rem Replaces the separate "Mods - ..." / "QA - ..." / "Dev - ..." .bat files.
setlocal EnableExtensions
title MKSM Komplete+
set "REPO=%~dp0"
set "TOOL=%REPO%mods\_build\modtool.py"
set "V1=%REPO%release\v1"
rem The ladder: dev builds tested on top of the newest frozen set, one rung at
rem a time. When a rung passes QA, freeze it into a new release\v1.x, point
rem BASE there and drop the mod from LADDER.
set "BASE=%REPO%release\v1.2"
set "BASE_NAME=v1.2 test build"
set LADDER="%REPO%mods\mksmk_probe"
set "LADDER_NAMES=(nothing on the ladder yet)"
where py >nul 2>nul && (set "PY=py -3") || (set "PY=python")
where pyw >nul 2>nul && (set "PYW=pyw -3") || (set "PYW=pythonw")
for /f %%e in ('echo prompt $E^| cmd') do set "E=%%e"
set "H=%E%[1;33m" & set "K=%E%[1;36m" & set "D=%E%[90m" & set "G=%E%[32m" & set "R=%E%[31m" & set "N=%E%[0m"
rem A folder dropped on this file: install the newest build of each mod in it.
if not "%~1"=="" (
    call :mods install "%~1"
    echo.
    pause
)

:menu
cls
echo.
echo   %H%MKSM Komplete+%N%   %D%dev menu%N%
echo   %D%----------------------------------------------------------------%N%
echo   %D%Installed now%N%
for /f "skip=1 tokens=*" %%l in ('%PY% "%TOOL%" list 2^>nul') do call :row "%%l"
echo   %D%----------------------------------------------------------------%N%
echo.
echo   %K%1%N%  Playtest           test set, then the QA console
echo   %K%2%N%  Test set           %BASE_NAME% + probe; dev %LADDER_NAMES%
echo   %K%3%N%  All dev builds     every mod's newest build + probe
echo   %K%4%N%  v1 release         what players have now (published)
echo   %K%5%N%  Pick levels        all dev builds, choose LDK and Shuffle
echo   %K%6%N%  Uninstall all      language packs stay; backups kept
echo.
echo   %K%7%N%  QA console         record, live state, notes, summary
echo   %K%8%N%  Installer window   the players' installer
echo   %K%Q%N%  Quit
echo.
choice /c 12345678q /n /m "  Pick: "
if errorlevel 9 goto :eof
goto opt%errorlevel%

:opt1
call :mods refresh "%BASE%" %LADDER% --with-probe || goto done
call :console
echo.
echo   %G%QA console opened.%N% Press %K%Start recording%N% there, then start the game yourself.
goto done

:opt2
call :mods refresh "%BASE%" %LADDER% --with-probe
goto done

:opt3
call :mods refresh "%REPO%mods" --with-probe
goto done

:opt4
call :mods refresh "%V1%"
goto done

:opt5
choice /c 234 /n /m "  Legendary Dark Knight: x2, x3 or x4? [2/3/4] "
if errorlevel 3 (set LDK=x4) else if errorlevel 2 (set LDK=x3) else (set LDK=x2)
choice /c nwc /n /m "  Shaolin Shuffle: Normal, Wild or Chaos? [N/W/C] "
if errorlevel 3 (set SHUFFLE=chaos) else if errorlevel 2 (set SHUFFLE=wild) else (set SHUFFLE=normal)
choice /c yn /n /m "  Include the MKSMK Probe? [Y/N] "
if errorlevel 2 (set PROBE=) else (set PROBE=--with-probe)
call :mods refresh "%REPO%mods" %PROBE% --ldk %LDK% --shuffle %SHUFFLE%
goto done

:opt6
choice /c yn /n /m "  Uninstall every mod (language packs stay)? [Y/N] "
if errorlevel 2 goto menu
call :mods uninstall-all
goto done

:opt7
call :console
goto menu

:opt8
start "" %PYW% "%REPO%tools\installer\mksmk_installer.pyw"
goto menu

:done
echo.
pause
goto menu

rem ---- helpers ----
:console
rem Console Python in a minimized window, not pyw: the console polls tasklist,
rem and under pyw every poll flashes a cmd window of its own.
start "MKSMK QA console" /min %PY% "%REPO%tools\qa_console\qa_console.py"
exit /b 0

:mods
echo.
tasklist /fi "imagename eq ShaolinMonksRecomp.exe" 2>nul | find /i "ShaolinMonksRecomp.exe" >nul && (
    echo   %R%Close the game and the launcher first.%N%
    exit /b 1
)
%PY% "%TOOL%" %*
if errorlevel 1 (echo   %R%modtool reported an error, see above.%N% & exit /b 1)
echo   %G%Done.%N%
exit /b 0

:row
rem (no if/else block: mod names have parentheses)
set "LINE=%~1"
if not "%LINE:~0,3%"=="[x]" goto row_off
echo     %G%[x]%N% %LINE:~4%
exit /b 0
:row_off
echo     %D%%LINE%%N%
exit /b 0
