@echo off
REM Build JingerPicManager Windows Release and copy the runnable bundle to output\
cd /d %~dp0

REM Prefer the known SDK location; fall back to PATH (i.e. a `flutter` on PATH).
if exist "K:\JingerNote\flutter\bin\flutter.bat" (
  set "FLUTTER=K:\JingerNote\flutter\bin\flutter.bat"
) else (
  set "FLUTTER=flutter"
)

%FLUTTER% build windows --release
if errorlevel 1 (
  echo BUILD FAILED
  exit /b 1
)

xcopy "build\windows\x64\runner\Release\*" "output\" /E /Y /I
echo Done. Artifacts are in output\
