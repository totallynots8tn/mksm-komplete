@echo off
rem Keeps every save.dat version and every game log while you play,
rem in qa\run-DATE-TIME next to this file. Start it before the game,
rem leave the window open, and press Ctrl+C when you are done.
cd /d "%~dp0"
where py >nul 2>nul
if %errorlevel%==0 (py -3 tools\qa_recorder\record.py %*) else (python tools\qa_recorder\record.py %*)
echo.
pause
