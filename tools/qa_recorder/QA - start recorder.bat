@echo off
rem Keeps every save.dat version and every game log while you play,
rem in qa\run-DATE-TIME next to this file. Start it before the game,
rem leave the window open, and press Ctrl+C when you are done.
rem Ships at the root of the contributor-tools zip (build_release.py), next to
rem tools\qa_recorder\record.py. In the repo, use MKSMK.bat > QA console instead.
cd /d "%~dp0"
where py >nul 2>nul
if %errorlevel%==0 (py -3 tools\qa_recorder\record.py %*) else (python tools\qa_recorder\record.py %*)
echo.
pause
