import sys
import io
import json
import os
import re
import socket
import time
import bugzilla

# 输出 UTF-8，配合 Rainmeter RunCommand 的 OutputType=UTF8 使用
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')

# 单台服务器超时时间（秒），避免一台连不上时卡住整个 Rainmeter
socket.setdefaulttimeout(15)

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG_PATH = os.environ.get("BUGLIST_CONFIG") or os.path.join(SCRIPT_DIR, "config.json")
CACHE_PATH = os.path.join(SCRIPT_DIR, "cache.txt")

# 两个 Bugzilla 共用同一套规则：只显示这些状态。
# 各站状态名写法不同（RootCaused / Root-Caused、NeedInfo / Need_Info、REOPENED / ReOpen），
# 所以先去掉 - _ 和空格、转小写再比较。
ACTIVE_STATUSES = {"assigned", "rootcaused", "needinfo", "new", "reopen", "reopened"}

# 显示顺序：越靠前越需要关注；同状态按 bug id 倒序（新的在前）
STATUS_PRIORITY = {
    "needinfo": 0,
    "assigned": 1,
    "rootcaused": 2,
    "new": 3,
    "reopen": 4,
    "reopened": 4,
}

# 服务器不支持查询合法状态列表时的兜底
FALLBACK_STATUSES = [
    "Assigned", "RootCaused", "Root-Caused", "NeedInfo", "Need_Info",
    "NEW", "ReOpen", "REOPENED",
]


def normalize(status):
    return re.sub(r"[-_\s]", "", status).lower()


def is_active(status):
    return normalize(status) in ACTIVE_STATUSES


def status_priority(status):
    return STATUS_PRIORITY.get(normalize(status), 9)


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
    # legal_values 是 python-bugzilla 的私有接口，失败时退回兜底列表。
    try:
        values = bz._proxy.Bug.legal_values({"field": "bug_status"})["values"]
        statuses = [v for v in values if is_active(v)]
    except Exception as e:
        print("[%s] 无法获取状态列表，使用兜底状态：%s" % (src.get("name", "?"), e),
              file=sys.stderr)
        statuses = FALLBACK_STATUSES
    if not statuses:
        return []
    return bz.query({"assigned_to": src["assigned_to"], "bug_status": statuses})


def read_cache_lines():
    """返回上次成功结果的 bug 行（不含 @status 行）。"""
    try:
        with open(CACHE_PATH, encoding="utf-8") as f:
            return [l for l in f.read().splitlines()
                    if l and not l.startswith("@status|")]
    except Exception:
        return []


def write_cache(text):
    # 用本机 ANSI 编码写入：Rainmeter 的 Lua 桥接按 ANSI 解释 Lua 字符串，
    # 缓存由 Lua 直接读入显示，因此不能写 UTF-8。
    try:
        with open(CACHE_PATH, "w", encoding="mbcs", errors="replace") as f:
            f.write(text)
    except Exception as e:
        print("写入缓存失败：%s" % e, file=sys.stderr)


def main():
    entries = []      # (排序键, 输出行)
    failed = []
    ok_count = 0

    for src in load_sources():
        try:
            bugs = fetch(src)
            ok_count += 1
        except Exception as e:  # 一台挂了不影响另一台
            failed.append(src.get("name", "?"))
            print("[%s] %s" % (src.get("name", "?"), e), file=sys.stderr)
            continue
        for bug in bugs:
            summary = " ".join(str(bug.summary).split())  # 压掉换行和多余空白
            key = (status_priority(bug.status), -int(bug.id))
            # 每行格式：<url>|<显示文本>，Lua 按第一个 | 拆开
            entries.append((key, "%s%d|%s%d-%s (%s)" % (
                src["base"], bug.id, src.get("tag", ""), bug.id, summary, bug.status)))

    entries.sort(key=lambda e: e[0])

    # 状态行：@status|<时间>|<失败源>|<失败字样>
    # 文字统一由这里提供，Lua 只做拼接，避免 Lua 源码里的中文经 Bang 传递时乱码。
    status_line = "@status|%s|%s|失败:" % (
        time.strftime("%m-%d %H:%M"), ",".join(failed))
    lines = [status_line] + [e[1] for e in entries]

    if ok_count == 0:
        # 全部数据源都失败：保留上次成功的结果，只更新状态行
        cached = read_cache_lines()
        if cached:
            lines = [status_line] + cached
    elif not entries:
        lines.append("没有找到分配给你的 Bug。")

    output = "\n".join(lines)
    print(output)

    # 至少有一个数据源成功时才覆盖缓存
    if ok_count > 0:
        write_cache(output)


if __name__ == "__main__":
    main()
