@echo off
setlocal

rem Bumps the build number, builds and deploys. Every deploy gets a new
rem build so "Check for updates" and the update banner can see it.
rem
rem   build_web.bat                                   bump build only
rem   build_web.bat -Version 1.1.0 -Notes "What's new"  new version + notes

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0release.ps1" %*
if %ERRORLEVEL% neq 0 (
    echo.
    echo Version bump failed. Nothing was built or deployed.
    exit /b %ERRORLEVEL%
)

call flutter build web --release --pwa-strategy=none
if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%

call firebase deploy
