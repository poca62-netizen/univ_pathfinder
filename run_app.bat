@echo off
setlocal
title Univ Pathfinder
cd /d "%~dp0"

set "FLUTTER_CMD="
for /f "delims=" %%F in ('where flutter.bat 2^>nul') do if not defined FLUTTER_CMD set "FLUTTER_CMD=%%F"
if not defined FLUTTER_CMD if exist "C:\src\flutter\bin\flutter.bat" set "FLUTTER_CMD=C:\src\flutter\bin\flutter.bat"

if not defined FLUTTER_CMD (
  echo Flutter was not found. Install Flutter and add its bin folder to PATH.
  pause
  exit /b 1
)

echo Preparing dependencies...
call "%FLUTTER_CMD%" pub get
if errorlevel 1 (
  echo Dependency setup failed. Check the message above.
  pause
  exit /b 1
)

if exist ".env.dev.json" (
  echo Starting Chrome with the development database settings...
  call "%FLUTTER_CMD%" run -d chrome --web-hostname=localhost --web-port=8080 --dart-define-from-file=.env.dev.json
) else (
  echo No .env.dev.json found. Starting demo mode without database access...
  call "%FLUTTER_CMD%" run -d chrome --web-hostname=localhost --web-port=8080 --dart-define=DEMO_MODE=true
)

if errorlevel 1 (
  echo The app could not start. Check the message above.
  pause
  exit /b 1
)
endlocal
