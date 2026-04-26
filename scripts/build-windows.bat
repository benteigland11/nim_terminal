@echo off
setlocal

cd /d "%~dp0\.."

nimble install -y --depsOnly
if errorlevel 1 exit /b %errorlevel%

nim c -d:release -o:nim_terminal.exe src\nim_terminal.nim
if errorlevel 1 exit /b %errorlevel%

echo Built nim_terminal.exe
