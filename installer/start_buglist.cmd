@echo off
setlocal
set "RM="

rem 先从卸载注册表项里找 Rainmeter 安装路径
for /f "tokens=2*" %%A in ('reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Rainmeter" /v InstallLocation 2^>nul') do if not "%%B"=="" set "RM=%%B\Rainmeter.exe"

rem 回退到默认安装路径
if not defined RM if exist "%ProgramW6432%\Rainmeter\Rainmeter.exe" set "RM=%ProgramW6432%\Rainmeter\Rainmeter.exe"
if not defined RM if exist "%ProgramFiles%\Rainmeter\Rainmeter.exe" set "RM=%ProgramFiles%\Rainmeter\Rainmeter.exe"
if not defined RM exit /b 1
if not exist "%RM%" exit /b 1

rem 启动 Rainmeter，然后重复刷新皮肤索引并激活 buglist（首启时索引可能还没就绪）
start "" "%RM%"
for /l %%i in (1,1,8) do (
  timeout /t 1 /nobreak >nul
  "%RM%" !RefreshApp
  "%RM%" !ActivateConfig "buglist" "bug_list.ini"
)
exit /b 0
