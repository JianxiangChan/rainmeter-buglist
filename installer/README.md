# 一键安装包

构建产物：`Output\BuglistSetup.exe`。目标机不需要预装 Python、python-bugzilla 或 Rainmeter。

## 构建步骤

1. 安装 Python 3.8+，并安装依赖：

   ```bash
   pip install pyinstaller python-bugzilla
   ```

2. 安装 [Inno Setup 6](https://jrsoftware.org/isdl.php)。

3. 运行构建脚本：

   ```powershell
   powershell -ExecutionPolicy Bypass -File build.ps1 -Python "C:\Path\To\python.exe"
   ```

   脚本会：
   - 用 PyInstaller 把 `bugzilla_rainmeter.py` 打成 `buglist.exe`（含 Python 与 python-bugzilla）；
   - 组织 `staging\skin\`，并把皮肤里的 `Program` 改为同目录的 `buglist.exe`；
   - 检查 `rainmeter\Rainmeter-4.5.28.exe`，没有则从官方 release 下载并校验 SHA-256；
   - 用 ISCC 编译 `buglist.iss`，输出 `Output\BuglistSetup.exe`。

## 安装包行为

- 检测目标机是否已安装 Rainmeter；没有则静默安装 Rainmeter 4.5.28。
- 把皮肤复制到 Rainmeter 的 `SkinPath\buglist`（默认 `文档\Rainmeter\Skins\buglist`，如果用户改过 `SkinPath` 会按 `Rainmeter.ini` 里的路径）。
- 安装完成后自动启动 Rainmeter，并反复重试 `!RefreshApp` + `!ActivateConfig`，确保皮肤被加载（首次启动时皮肤索引可能还没就绪）。
- 默认创建开机自启快捷方式（安装向导中可取消），登录后自动启动并显示。
- 首次安装时用 `config.example.json` 生成 `config.json`，并打开记事本让用户填写。
- 安装需要管理员权限（用于静默安装 Rainmeter）。
- 卸载时保留用户填写好的 `config.json`。

## 注意

- 目标机首次使用仍需填写自己的 Bugzilla 地址、账号和 API Key，安装包不能内置凭据。
- `rainmeter\Rainmeter-4.5.28.exe`、`staging\`、`Output\`、`build\` 都是构建产物，不提交到仓库。
- Rainmeter 为 GPL 项目；对外分发安装包时请附上其许可证与来源。
