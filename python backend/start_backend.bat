@echo off
setlocal

cd /d "%~dp0"

set PYTHON_BIN=python
if not "%1"=="" set PYTHON_BIN=%1

%PYTHON_BIN% backend_launcher.py
if errorlevel 1 (
  echo.
  echo Launcher exited with an error.
  pause
  exit /b 1
)

endlocal
