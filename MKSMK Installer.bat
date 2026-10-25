@echo off
rem Open the MKSMK Mod Installer window (needs Python 3.11+ from python.org).
where pyw >nul 2>nul
if %errorlevel%==0 (start "" pyw -3 "%~dp0tools\installer\mksmk_installer.pyw") else (start "" pythonw "%~dp0tools\installer\mksmk_installer.pyw")
