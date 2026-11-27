import sys
import io
import json
import os
import re
import socket
import bugzilla

# 输出 UTF-8，配合 Rainmeter RunCommand 的 OutputType=UTF8 使用
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')

# 单台服务器超时时间（秒），避免一台连不上时卡住整个 Rainmeter
socket.setdefaulttimeout(15)

# 账号、API Key、服务器地址都放在同目录的 config.json（不提交到仓库）。
# 也可以用环境变量 BUGLIST_CONFIG 指定其他路径。
CONFIG_PATH = os.environ.get("BUGLIST_CONFIG") or os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "config.json")

# 两个 Bugzilla 共用同一套规则：只显示这些状态。
# 各站状态名写法不同（RootCaused / Root-Caused、NeedInfo / Need_Info、ReOPENED / ReOpen），
# 所以先去掉 - _ 和空格、转小写再比较。
ACTIVE_STATUSES = {"assigned", "rootcaused", "needinfo", "new", "reopen", "reopened"}


def is_active(status):
    return re.sub(r"[-_\s]", "", status).lower() in ACTIVE_STATUSES


def load_sources():
    if not os.path.exists(CONFIG_PATH):
        print("缺少配置文件 config.json，请复制 config.example.json 并填写账号与 API Key。")
        sys.exit(1)
    try:
        with open(CONFIG_PATH, encoding="utf-8-sig") as f:
            return json.load(f).get("sources", [])
    except Exception as e:
        print("配置文件 config.json 读取失败：%s" % e)
        sys.exit(1)


def fetch(src):
    bz = bugzilla.Bugzilla(url=src["url"], api_key=src["api_key"])
    # 取该服务器自己的合法状态名，用上面同一条规则筛出“活跃状态”再查，
    # 避免不带状态过滤的全量查询（本地服务器上要 90s 以上）。
    values = bz._proxy.Bug.legal_values({"field": "bug_status"})["values"]
    statuses = [v for v in values if is_active(v)]
    if not statuses:
        return []
    return bz.query({"assigned_to": src["assigned_to"], "bug_status": statuses})


def main():
    # 每行格式：<url>|<显示文本>，Lua 按第一个 | 拆开
    lines = []
    for src in load_sources():
        try:
            bugs = fetch(src)
        except Exception as e:  # 一台挂了不影响另一台
            print("[%s] %s" % (src.get("name", "?"), e), file=sys.stderr)
            continue
        for bug in bugs:
            summary = " ".join(str(bug.summary).split())  # 压掉换行和多余空白
            lines.append("%s%d|%s%d-%s (%s)" % (
                src["base"], bug.id, src.get("tag", ""), bug.id, summary, bug.status))

    if not lines:
        print("没有找到分配给你的 Bug。")
        return
    print("\n".join(lines))


if __name__ == "__main__":
    main()
