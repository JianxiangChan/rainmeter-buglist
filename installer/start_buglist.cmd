@echo off
setlocal
set "RM="
for /f "tokens=2*" %%A in ('reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Rainmeter" /v InstallLocation 2^>nul') do if not "%%B"=="" set "RM=%%B\Rainmeter.exe"
if not defined RM for /f "tokens=2*" %%A in ('reg query "HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Rainmeter" /v InstallLocation 2^>nul') do if not "%%B"=="" set "RM=%%B\Rainmeter.exe"
if not defined RM if exist "%ProgramW6432%\Rainmeter\Rainmeter.exe" set "RM=%ProgramW6432%\Rainmeter\Rainmeter.exe"
if not defined RM if exist "%ProgramFiles%\Rainmeter\Rainmeter.exe" set "RM=%ProgramFiles%\Rainmeter\Rainmeter.exe"
if not defined RM exit /b 1
if not exist "%RM%" exit /b 1
start "" "%RM%"
for /l %%i in (1,1,8) do (
  ping -n 2 127.0.0.1 >nul
  "%RM%" !RefreshApp
  "%RM%" !ActivateConfig "buglist" "bug_list.ini"
)
exit /b 0
