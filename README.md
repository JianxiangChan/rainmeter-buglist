# Rainmeter Buglist

一个 Rainmeter 桌面小部件：定时查询 Bugzilla，把分配给你的、仍需关注的 bug 列在桌面上，点击可直接打开对应 bug 页面。

支持同时查询多个 Bugzilla 实例，每行显示 `[标签]ID-标题 (状态)`，按状态着色：

| 状态 | 颜色 |
| --- | --- |
| Assigned | 橙色 |
| NeedInfo / Need_Info | 红色 |
| RootCaused / Root-Caused | 绿色 |
| NEW / ReOpen / UNCONFIRMED | 红色 |
| 其他 | 灰色 |

## 目录结构

| 文件 | 说明 |
| --- | --- |
| `bug_list.ini` | Rainmeter 皮肤定义（布局、刷新周期、Python 调用） |
| `bug_list.lua` | 解析 Python 输出，填充分行文本 / 颜色 / 点击链接 / 悬浮提示 |
| `bugzilla_rainmeter.py` | 查询 Bugzilla 并输出 `URL|显示文本` 行 |
| `config.json` | **本地私有配置**（服务器地址、账号、API Key），不提交 |
| `config.example.json` | 配置模板 |
| `.gitignore` | 忽略 `config.json` 等本地文件 |

## 依赖

- [Rainmeter](https://www.rainmeter.net/) 4.5+（内置 RunCommand 插件）
- Python 3.8+
- `pip install python-bugzilla`

## 使用

1. 把本目录放到 Rainmeter 的 `Skins` 目录下，例如
   `C:\Users\<你>\Documents\Rainmeter\Skins\buglist`。
2. 复制配置模板并填写自己的信息：

   ```bash
   cp config.example.json config.json
   ```

   `sources` 里每一项对应一台 Bugzilla：

   | 字段 | 说明 |
   | --- | --- |
   | `name` | 数据源名称，仅用于报错日志 |
   | `tag` | 显示前缀，例如 `[U]`；不需要就留空 |
   | `url` | XML-RPC 地址，通常是 `<站点>/xmlrpc.cgi` |
   | `api_key` | Bugzilla API Key（在站点的 Preferences → API Keys 生成） |
   | `base` | bug 页面地址前缀，用于点击跳转 |
   | `assigned_to` | 要查询的账号邮箱（注意各站点账号可能不同） |

3. 修改 `bug_list.ini` 里的 Python 路径，使其指向本机安装位置：

   ```ini
   Program="C:\...\python.exe"
   Parameter="C:\...\Skins\buglist\bugzilla_rainmeter.py"
   ```

4. 在 Rainmeter 中加载 `buglist\bug_list.ini`。

## 显示规则

- 只显示"活跃状态"的 bug（`Assigned`、`RootCaused`/`Root-Caused`、`NeedInfo`/`Need_Info`、`NEW`、`ReOpen`/`REOPENED`）。
  判断时会把状态名去掉 `-`、`_`、空格并转小写，因此不同 Bugzilla 的状态命名差异无需分别配置。规则见 `bugzilla_rainmeter.py` 的 `ACTIVE_STATUSES`。
- 已关闭的状态（Closed、Fixed、Verified、WONTFIX 等）不显示。
- 每 60 秒刷新一次；最多显示 8 行（`bug_list.ini` 的 `MaxBug`）。
- 标题过长会截断，鼠标悬停可看完整标题。

## 隐私

`config.json` 含有账号与 API Key，已被 `.gitignore` 排除，不会被提交。请勿把它提交到任何仓库；如果不慎泄露，请到 Bugzilla 的 API Keys 页面吊销并重新生成。
