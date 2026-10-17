@echo off
setlocal

if "%~1"=="" (
    echo Usage: release.bat ^<version^> ["release notes"]
    echo Example: release.bat 1.0.1 "Fixed chat bubble spacing"
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0release.ps1" -Version "%~1" -Notes "%~2"

if %ERRORLEVEL% neq 0 (
    echo.
    echo Release failed. Nothing was built or committed.
    exit /b %ERRORLEVEL%
)