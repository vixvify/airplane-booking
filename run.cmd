@echo off
setlocal
cd /d "%~dp0"
set "GIT_BASH=%ProgramFiles%\Git\bin\bash.exe"
if not exist "%GIT_BASH%" set "GIT_BASH=%LocalAppData%\Programs\Git\bin\bash.exe"
if not exist "%GIT_BASH%" (
  echo Git Bash was not found. Install Git for Windows or update run.cmd.
  pause
  exit /b 1
)
"%GIT_BASH%" -lc "bash scripts/menu.sh"
if errorlevel 1 pause
