@echo off
setlocal

if "%~1"=="" (
    echo Usage: release.bat ^<version^> ["release notes"]
    echo Example: release.bat 1.0.1 "Fixed chat bubble spacing"
    exit /b 1
)

rem Same as build_web.bat, with a new version number and release notes.
call "%~dp0build_web.bat" -Version "%~1" -Notes "%~2"
