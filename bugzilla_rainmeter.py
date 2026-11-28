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
if getattr(sys, "frozen", False):
    # PyInstaller 单文件模式下 __file__ 指向临时解压目录，配置/缓存应放在 exe 旁边
    SCRIPT_DIR = os.path.dirname(os.path.abspath(sys.executable))
CONFIG_PATH = os.environ.get("BUGLIST_CONFIG") or os.path.join(SCRIPT_DIR, "config.json")
CACHE_PATH = os.path.join(SCRIPT_DIR, "cache.txt")
STATE_PATH = os.path.join(SCRIPT_DIR, "state.json")
ACK_PATH = os.path.join(SCRIPT_DIR, "ack.txt")

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
        return [], {}

    bugs = bz.query({"assigned_to": src["assigned_to"], "bug_status": statuses})

    # 再取一次评论数，用于检测“有新评论”
    comment_counts = {}
    if bugs:
        try:
            result = bz._proxy.Bug.comments({"ids": [int(b.id) for b in bugs]})
            for bug_id, data in result.get("bugs", {}).items():
                comment_counts[str(bug_id)] = len(data.get("comments", []))
        except Exception as e:
            print("[%s] 获取评论失败，退回 last_change_time：%s"
                  % (src.get("name", "?"), e), file=sys.stderr)
    return bugs, comment_counts


def load_state():
    """返回上次每个数据源的快照；没有 state.json 时返回 None。"""
    if not os.path.exists(STATE_PATH):
        return None
    try:
        with open(STATE_PATH, encoding="utf-8") as f:
            return json.load(f).get("sources", {})
    except Exception as e:
        print("读取 state.json 失败：%s" % e, file=sys.stderr)
        return None


def save_state(sources_state):
    try:
        with open(STATE_PATH, "w", encoding="utf-8") as f:
            json.dump({"sources": sources_state}, f, ensure_ascii=False, indent=2)
    except Exception as e:
        print("写入 state.json 失败：%s" % e, file=sys.stderr)


def is_changed(prev_snapshot, bug_id, status, summary, comment_count=None, last_change=None):
    """prev_snapshot 为 None（首次运行或新数据源）时不算变化，避免一开始全部闪烁。"""
    if prev_snapshot is None:
        return False
    old = prev_snapshot.get(str(bug_id))
    if old is None:
        return True
    if old.get("changed"):
        return True      # 之前的变化还没被点击确认，继续闪烁
    if old.get("status") != status or old.get("summary") != summary:
        return True
    old_count = old.get("comment_count")
    if old_count is not None and comment_count is not None and old_count != comment_count:
        return True      # 有新评论（或评论被删）
    if comment_count is None:
        # 评论接口不可用时，退回 last_change_time（任何修改都会变）
        old_lc = old.get("last_change")
        if old_lc is not None and last_change is not None and old_lc != last_change:
            return True
    return False


def read_acks():
    """读取用户点击过的 bug URL（Lua 在点击时追加写入）。"""
    try:
        with open(ACK_PATH, encoding="utf-8", errors="replace") as f:
            return {line.strip() for line in f if line.strip()}
    except Exception:
        return set()


def write_acks(urls):
    try:
        if urls:
            with open(ACK_PATH, "w", encoding="utf-8") as f:
                f.write("\n".join(sorted(urls)) + "\n")
        elif os.path.exists(ACK_PATH):
            os.remove(ACK_PATH)
    except Exception as e:
        print("写入 ack.txt 失败：%s" % e, file=sys.stderr)


def read_cache_lines():
    """返回上次成功结果的 bug 行（不含 @status 行）。"""
    try:
        with open(CACHE_PATH, encoding="mbcs", errors="replace") as f:
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
    sources = load_sources()
    prev_state = load_state()
    state = dict(prev_state) if prev_state else {}
    acked = read_acks()
    seen_urls = set()

    entries = []      # (排序键, url, 显示文本, 是否变化)
    failed = []
    ok_count = 0

    for src in sources:
        name = src.get("name", "?")
        try:
            bugs, comment_counts = fetch(src)
            ok_count += 1
        except Exception as e:  # 一台挂了不影响另一台
            failed.append(name)
            print("[%s] %s" % (name, e), file=sys.stderr)
            continue

        prev = None if prev_state is None else prev_state.get(name)
        snapshot = {}
        for bug in bugs:
            summary = " ".join(str(bug.summary).split())  # 压掉换行和多余空白
            url = "%s%d" % (src["base"], bug.id)
            seen_urls.add(url)

            comment_count = comment_counts.get(str(bug.id))
            lc = getattr(bug, "last_change_time", None)
            last_change = str(lc) if lc else None

            changed = is_changed(prev, bug.id, bug.status, summary,
                                 comment_count, last_change)
            if url in acked:      # 用户已经点过这行，不再闪烁
                changed = False

            snapshot[str(bug.id)] = {
                "status": bug.status,
                "summary": summary,
                "comment_count": comment_count,
                "last_change": last_change,
                "changed": changed,
            }
            entries.append((
                (status_priority(bug.status), -int(bug.id)),
                url,
                "%s%d-%s (%s)" % (src.get("tag", ""), bug.id, summary, bug.status),
                changed,
            ))
        state[name] = snapshot

    entries.sort(key=lambda e: e[0])

    # 状态行：@status|<时间>|<失败源>|<失败字样>
    # 文字统一由这里提供，Lua 只做拼接，避免 Lua 源码里的中文经 Bang 传递时乱码。
    status_line = "@status|%s|%s|失败:" % (
        time.strftime("%m-%d %H:%M"), ",".join(failed))

    # 有变化的行在文本前加 "!"，Lua 据此让该行持续闪烁，直到被点击
    live_lines = [status_line] + [
        "%s|%s%s" % (url, "!" if changed else "", text)
        for _, url, text, changed in entries
    ]

    if ok_count == 0:
        # 全部数据源都失败：保留上次成功的结果，只更新状态行
        cached = read_cache_lines()
        if cached:
            live_lines = [status_line] + cached
    elif not entries:
        live_lines.append("没有找到分配给你的 Bug。")

    print("\n".join(live_lines))

    # 至少有一个数据源成功时才覆盖缓存（缓存保留变化标记，刷新后仍会闪烁）
    if ok_count > 0:
        write_cache("\n".join(live_lines))
    save_state(state)
    # 已经确认过的 URL 移出 ack.txt；本轮没查到的保留，等下次再处理
    write_acks(acked - seen_urls)


if __name__ == "__main__":
    main()
