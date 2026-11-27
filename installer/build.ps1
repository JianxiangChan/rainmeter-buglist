param(
    [string]$Python = "python",
    [string]$Iscc = "",
    [switch]$SkipExe
)

$ErrorActionPreference = "Stop"
$here = $PSScriptRoot
$root = Split-Path -Parent $here
$stageSkin = Join-Path $here "staging\skin"
$buildDir = Join-Path $here "build"

# 1) 用 PyInstaller 打包成独立 exe（含 Python 与 python-bugzilla）
if (-not $SkipExe) {
    Remove-Item $buildDir -Recurse -Force -ErrorAction SilentlyContinue
    & $Python -m PyInstaller --onefile --noconfirm --clean --name buglist `
        --distpath (Join-Path $buildDir "dist") `
        --workpath (Join-Path $buildDir "work") `
        --specpath $buildDir `
        (Join-Path $root "bugzilla_rainmeter.py")
    if ($LASTEXITCODE -ne 0) { throw "PyInstaller 构建失败" }
}

# 2) 组织要安装的皮肤目录
Remove-Item $stageSkin -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $stageSkin -Force | Out-Null
foreach ($f in @("bug_list.lua", "config.example.json", "README.md", "LICENSE", "screenshot.png")) {
    Copy-Item (Join-Path $root $f) $stageSkin
}
Copy-Item (Join-Path $buildDir "dist\buglist.exe") $stageSkin

# 打包版皮肤改用同目录的 buglist.exe，不再依赖本机安装的 Python
$ini = Get-Content (Join-Path $root "bug_list.ini") -Raw -Encoding UTF8
$ini = $ini -replace 'Program="#PythonPath#"', 'Program="#CURRENTPATH#buglist.exe"'
$ini = $ini -replace 'Parameter="#CURRENTPATH#bugzilla_rainmeter.py"', 'Parameter='
[IO.File]::WriteAllText((Join-Path $stageSkin "bug_list.ini"), $ini,
    (New-Object System.Text.UTF8Encoding($false)))

# 3) 准备 Rainmeter 安装包（没有则下载并校验）
$rmDir = Join-Path $here "rainmeter"
$rmExe = Join-Path $rmDir "Rainmeter-4.5.28.exe"
$rmHash = "de6e010f8c28882bc28dcd8f319c899f34dfddec51e1e4dd4e7a23f68ebfe14d"
if (-not (Test-Path $rmExe)) {
    New-Item -ItemType Directory -Path $rmDir -Force | Out-Null
    Write-Host "下载 Rainmeter 安装包..."
    Invoke-WebRequest -Uri "https://github.com/rainmeter/rainmeter/releases/download/v4.5.28.3936/Rainmeter-4.5.28.exe" -OutFile $rmExe
}
$hash = (Get-FileHash $rmExe -Algorithm SHA256).Hash.ToLower()
if ($hash -ne $rmHash) { throw "Rainmeter 安装包校验失败: $hash" }

# 4) 编译安装包
if ($Iscc -eq "") {
    $candidates = @(
        "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
        "C:\Program Files\Inno Setup 6\ISCC.exe",
        (Join-Path $env:LOCALAPPDATA "Programs\Inno Setup 6\ISCC.exe")
    )
    $Iscc = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $Iscc) { throw "找不到 ISCC.exe，请安装 Inno Setup 6 或通过 -Iscc 指定路径" }

Push-Location $here
try {
    & $Iscc "buglist.iss"
    if ($LASTEXITCODE -ne 0) { throw "ISCC 编译失败" }
} finally {
    Pop-Location
}

Write-Host ""
Write-Host "完成：$here\Output\BuglistSetup.exe"
