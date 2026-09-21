#!/usr/bin/env bash
# 為什麼需要這支腳本：
# statusline tee 要生效，Claude Code 呼叫的那條命令就必須改成先經過 wrapper。
# 那條命令住在 ~/.claude/settings.json —— 一個同時放著 hooks、plugin 設定、
# 主題的檔案。改壞它不是「功能沒生效」，是使用者的環境壞掉。
#
# 所以這支腳本的預設行為是「只印 diff，什麼都不改」。要真的動手得明講 --apply。
#
#   bash scripts/install_statusline_tee.sh              # 看 diff
#   bash scripts/install_statusline_tee.sh --apply      # 安裝
#   bash scripts/install_statusline_tee.sh --uninstall --apply   # 還原
#
# 環境變數 QM_CLAUDE_DIR 可以指到別的目錄（測試用，預設 ~/.claude）。
#
# 保證（每一條都有對應的測試，見 scripts/test_install_statusline_tee.sh）：
#   - 只有 statusLine.command 這一個字串會變，檔案其餘 byte 完全不動
#   - 動手之前一定留下時間戳備份
#   - 原本的命令字串原樣存進 quotamonster-tee.original，--uninstall 逐 byte 還原
#   - 看不懂的設定（沒有 statusLine、命令不是可執行檔、JSON 壞掉）一律拒絕，不猜
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAUDE_DIR="${QM_CLAUDE_DIR:-$HOME/.claude}"

MODE=show
ACTION=install
for arg in "$@"; do
  case "$arg" in
    --apply)     MODE=apply ;;
    --uninstall) ACTION=uninstall ;;
    -h|--help)
      # 從第 2 行開始印註解，遇到第一行不是註解就停。
      # 寫死行號會在說明變長變短時把 set -euo pipefail 當成說明印出來。
      awk 'NR>1 { if ($0 !~ /^#/) exit; sub(/^# ?/, ""); print }' "${BASH_SOURCE[0]}"
      exit 0 ;;
    *)
      echo "✗ 不認得的參數：$arg" >&2
      exit 2 ;;
  esac
done

exec python3 - "$ROOT" "$CLAUDE_DIR" "$MODE" "$ACTION" <<'PY'
import difflib, json, os, shlex, shutil, sys, time

ROOT, CLAUDE_DIR, MODE, ACTION = sys.argv[1:5]

SETTINGS    = os.path.join(CLAUDE_DIR, "settings.json")
# dotfiles 管理工具（stow / chezmoi / yadm）會把 settings.json 做成 symlink。
# os.replace() 換掉的是**連結本身**，會把 symlink 變成普通檔，
# 而 dotfiles 倉庫裡那份從此被孤立、使用者的還原流程也失效。
# 所有讀寫都走 realpath。
SETTINGS_REAL = os.path.realpath(SETTINGS)
WRAPPER_SRC = os.path.join(ROOT, "scripts", "quotamonster-tee.sh")
WRAPPER_DST = os.path.join(CLAUDE_DIR, "quotamonster-tee.sh")
ORIGINAL    = os.path.join(CLAUDE_DIR, "quotamonster-tee.original")
MARKER      = "quotamonster-tee.sh"


def die(msg):
    print("✗ " + msg, file=sys.stderr)
    sys.exit(1)


def shell_quote(path):
    """把絕對路徑變成一段安全的 shell 字面量。

    在 $HOME 底下的路徑寫成 "$HOME/..." —— 使用者打開 settings.json 一眼看得懂，
    而且換帳號也還能動。路徑裡有會被 shell 再解讀的字元時退回 shlex.quote，
    寧可醜一點也不要產生一條會壞掉的命令。
    """
    home = os.path.expanduser("~")
    if path.startswith(home + os.sep):
        rest = path[len(home) + 1:]
        if not any(c in rest for c in '"$`\\'):
            return '"$HOME/%s"' % rest
    return shlex.quote(path)


def expand(cmd):
    """把設定裡的命令字串解析成一個檔案路徑，解析不出來就回 None。"""
    try:
        parts = shlex.split(cmd)
    except ValueError:
        return None
    if len(parts) != 1:
        return None                      # 帶參數 → 不是單純的腳本路徑
    p = os.path.expanduser(os.path.expandvars(parts[0]))
    return p if os.path.isfile(p) and os.access(p, os.X_OK) else None


def read_settings():
    if not os.path.isfile(SETTINGS_REAL):
        die("找不到 %s —— 這台機器沒有使用者層級的 Claude Code 設定？" % SETTINGS)
    # newline="" 關掉 universal newline 轉換。少了它，CRLF 的 settings.json
    # 讀進來就變成 LF，「逐 byte 相同的備份」根本不是逐 byte 相同。
    raw = open(SETTINGS_REAL, encoding="utf-8", newline="").read()
    try:
        data = json.loads(raw)
    except Exception as e:
        die("%s 不是合法的 JSON（%s）。不動它，先自己看一眼。" % (SETTINGS, e))
    return raw, data


def current_command(data):
    sl = data.get("statusLine")
    if not isinstance(sl, dict):
        die("settings.json 裡沒有 statusLine 設定。\n"
            "  tee 是包在既有的狀態列腳本外面的，沒有原本的腳本就沒有東西可以包。\n"
            "  先用 /statusline 設定好狀態列，再回來跑這支腳本。")
    if sl.get("type") != "command":
        die('statusLine.type 是 %r，不是 "command"。不認得的形狀，不動。' % sl.get("type"))
    cmd = sl.get("command")
    if not isinstance(cmd, str) or not cmd.strip():
        die("statusLine.command 不是一個字串。不認得的形狀，不動。")
    return cmd


def encodings_of(value):
    """一個字串在 JSON 檔裡可能長的兩種樣子。

    很多工具（Python 的 json.dump 預設、不少格式化器）會把非 ASCII 寫成 \\uXXXX。
    比對與寫回都必須用**同一種**寫法，否則 --uninstall 還原出來的 byte 會與原檔不同。
    """
    literal = json.dumps(value, ensure_ascii=False)
    escaped = json.dumps(value)
    return [literal] if literal == escaped else [literal, escaped]


def swap_command(raw, old_cmd, new_cmd):
    """只換 command 那一個字串，其餘 byte 一個都不動。

    出現次數（兩種跳脫寫法加總）不是剛好一次就拒絕動手 ——
    寧可不動，也不要改到別的地方（例如剛好也跑同一支腳本的某個 hook）。
    """
    variants = encodings_of(old_cmd)
    total = sum(raw.count(v) for v in variants)
    if total != 1:
        die("在 settings.json 裡找到 %d 處與 statusLine.command 相同的字面量，\n"
            "  沒辦法保證只改到那一個。不動。" % total)
    needle = next(v for v in variants if raw.count(v) == 1)
    # 用與原檔相同的跳脫風格寫回去
    escaped_style = (needle == json.dumps(old_cmd))
    out = raw.replace(needle, json.dumps(new_cmd, ensure_ascii=escaped_style), 1)

    # 改完要能 parse，而且除了那一個字串以外整棵樹都一樣
    before = json.loads(raw)
    after = json.loads(out)
    before["statusLine"] = dict(before["statusLine"]); before["statusLine"].pop("command", None)
    probe = json.loads(out)
    probe["statusLine"] = dict(probe["statusLine"]); probe["statusLine"].pop("command", None)
    if before != probe or after["statusLine"]["command"] != new_cmd:
        die("改寫後的 settings.json 與預期不符。已中止，原檔未動。")
    return out


def show_diff(raw, out):
    print("".join(difflib.unified_diff(
        raw.splitlines(keepends=True), out.splitlines(keepends=True),
        fromfile=SETTINGS, tofile=SETTINGS + "（改後）")), end="")


def install_wrapper():
    """把 wrapper 換成 repo 裡的版本 —— **原子地**。

    ⚠️ 原本用 shutil.copyfile 就地覆寫，而那支檔案**正在被每一次狀態列渲染呼叫**。
    〔實測 2026-09-21〕把全長 5506 byte 的 wrapper 截成各種長度餵給 bash：
    12 種殘檔的 stdout **全部是 0 byte**（＝狀態列整條空白）；其中 2850/3000/5445
    byte 的殘檔 rc=1 且完全不叫內層，5445 那個甚至已經把快取寫出去了；
    2200/3500/4000/4900/5100 byte 則是 rc=2 語法錯誤。
    copyfile 的 truncate 空窗只有微秒級〔推論：與 3 秒一次的渲染重疊機率很低，
    我沒有量過那個機率〕，但這個風險完全不需要存在 —— rename 是原子的。
    """
    tmp = WRAPPER_DST + ".qm-tmp"
    shutil.copyfile(WRAPPER_SRC, tmp)
    os.chmod(tmp, 0o755)
    os.replace(tmp, WRAPPER_DST)


def write_atomically(path, text):
    """原子換檔，而且**保留目標原本的權限**。

    ⚠️ os.replace() 換上去的是新建的那個檔，它的權限由當下的 umask 決定，
    不會繼承被換掉的那一個。〔實測 2026-09-21〕一個原本 0600 的 settings.json
    （裡面放 hooks 與 env）裝完之後變成 **0644** —— 同群組與其他使用者都讀得到。
    這支腳本的整個賣點是「只動 statusLine.command 這一個字串」，
    把權限放寬顯然不在那個承諾裡面。
    """
    tmp = path + ".qm-tmp"
    try:
        mode = os.stat(path).st_mode & 0o7777
    except OSError:
        mode = None                      # 目標還不存在 → 沒有東西要保留
    with open(tmp, "w", encoding="utf-8", newline="") as f:
        f.write(text)
    if mode is not None:
        os.chmod(tmp, mode)              # 要在 replace **之前**，否則有一瞬間是寬的
    os.replace(tmp, path)


def backup(raw):
    dst = "%s.bak-%s" % (SETTINGS, time.strftime("%Y%m%d-%H%M%S"))
    with open(dst, "w", encoding="utf-8", newline="") as f:
        f.write(raw)
    return dst


# ── install ──────────────────────────────────────────────────────
def install():
    raw, data = read_settings()
    cmd = current_command(data)

    if MARKER in cmd:
        # 已經裝過了。只把 wrapper 更新成 repo 裡的最新版，設定不動。
        if MODE == "apply":
            install_wrapper()
            print("✓ 已經安裝過，只更新了 %s" % WRAPPER_DST)
        else:
            print("✓ 已經安裝過，settings.json 不需要改動")
        return 0

    inner = expand(cmd)
    if inner is None:
        die("目前的 statusLine.command 不是一個可執行的腳本檔：\n"
            "      %s\n"
            "  這支安裝腳本只會包裝「一個可執行檔」。帶參數的命令、或是像\n"
            "  npx 這種要另外解析的寫法，包起來的風險比收益高，所以不猜。\n"
            "  要的話請自己把那條命令改成一個腳本檔再回來。" % cmd)

    new_cmd = "QM_STATUSLINE_INNER=%s %s" % (shell_quote(inner), shell_quote(WRAPPER_DST))
    out = swap_command(raw, cmd, new_cmd)

    print("▸ 會安裝：%s" % WRAPPER_DST)
    print("▸ 內層仍然是：%s" % inner)
    print()
    show_diff(raw, out)
    print()

    if MODE != "apply":
        print("（這是預覽。確認沒問題後加 --apply 才會真的改。）")
        return 0

    bak = backup(raw)
    install_wrapper()
    with open(ORIGINAL, "w", encoding="utf-8") as f:
        f.write(cmd)                      # 原樣保存，--uninstall 才能逐 byte 還原
    write_atomically(SETTINGS_REAL, out)

    print("✓ 備份：%s" % bak)
    print("✓ 原本的命令已存進：%s" % ORIGINAL)
    print("✓ 已安裝。下一次狀態列重新渲染時就會開始寫快取（改 command 會跳過 debounce，通常是立刻）。")
    return 0


# ── uninstall ────────────────────────────────────────────────────
def uninstall():
    raw, data = read_settings()
    cmd = current_command(data)

    if MARKER not in cmd:
        print("✓ statusLine.command 本來就沒有經過 tee，沒有東西要還原")
        return 0

    if not os.path.isfile(ORIGINAL):
        die("找不到 %s，無法逐 byte 還原原本的命令。\n"
            "  請自己從 %s.bak-* 裡挑一份回復。" % (ORIGINAL, SETTINGS))
    old_cmd = open(ORIGINAL, encoding="utf-8").read()

    out = swap_command(raw, cmd, old_cmd)
    show_diff(raw, out)
    print()

    if MODE != "apply":
        print("（這是預覽。確認沒問題後加 --apply 才會真的改。）")
        return 0

    bak = backup(raw)
    write_atomically(SETTINGS_REAL, out)
    for p in (WRAPPER_DST, ORIGINAL):
        if os.path.exists(p):
            os.remove(p)

    print("✓ 備份：%s" % bak)
    print("✓ 已還原，wrapper 已移除。快取目錄沒有動，要清自己刪。")
    return 0


sys.exit(install() if ACTION == "install" else uninstall())
PY
