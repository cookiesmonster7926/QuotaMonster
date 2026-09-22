#!/usr/bin/env bash
# 為什麼需要這支腳本：
# statusline tee 唯一不可妥協的承諾是「使用者的狀態列一個 byte 都不變」。
# Swift 那邊的單元測試碰不到這件事 —— 它發生在 shell 層，而且錯了不會拋例外，
# 只會讓使用者的狀態列悄悄變空白（官方文件：離開碼非 0 或輸出為空 → 整條變空白）。
#
# 所以這支腳本用對照組的方式測：同一份 payload 分別
#   (a) 直接餵給內層腳本
#   (b) 餵給 wrapper
# 然後比對 stdout、stderr、離開碼三者，任何一個不同就算失敗。
#
# 跑兩輪：
#   第一輪 內層 = 本檔內建的 stub，行為固定，任何機器都跑得出同樣結果（回歸測試）
#   第二輪 內層 = 使用者真正的 ~/.claude/statusline.sh（驗收測試，不存在就跳過）
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WRAPPER="$ROOT/scripts/quotamonster-tee.sh"

if [[ ! -x "$WRAPPER" ]]; then
  echo "✗ 找不到可執行的 wrapper：$WRAPPER" >&2
  exit 1
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/qm-tee-test.XXXXXX")"

# 這支腳本自己壞掉（unbound variable、語法錯）時絕不可以回報成功 ——
# 一個「沒跑完但離開碼 0」的測試比沒有測試更危險。
REACHED_END=0
cleanup() {
  local rc=$?
  rm -rf "$WORK"
  if (( REACHED_END == 0 )); then
    echo "✗ 測試腳本在跑完之前就中斷了（rc=${rc}）" >&2
    exit 1
  fi
  exit "$rc"
}
trap cleanup EXIT

PASS=0
FAIL=0

# ── 內建 stub 內層腳本 ───────────────────────────────────────────
# 刻意模仿使用者腳本的三個關鍵行為：讀 stdin 到 EOF、多行 ANSI 輸出、
# 空輸入時以非 0 收尾。wrapper 必須把這三件事原樣傳遞。
cat > "$WORK/stub-inner.sh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
input=$(cat)
if [[ -z "$input" ]]; then
  printf 'no input' >&2
  exit 1
fi
printf '\033[36m%s bytes\033[0m\n\033[90m%s\033[0m' \
  "${#input}" "$(printf '%s' "$input" | cksum | cut -d' ' -f1)"
STUB
chmod +x "$WORK/stub-inner.sh"

# ── 測試 payload ─────────────────────────────────────────────────
python3 - "$WORK/cases" <<'PY'
import json, os, sys
d = sys.argv[1]
os.makedirs(d, exist_ok=True)

base = {
    "session_id": "11111111-1111-4111-8111-111111111111",
    "transcript_path": "/tmp/fixture-project/t.jsonl",
    "cwd": "/tmp/fixture-project",
    "model": {"id": "claude-opus-5", "display_name": "Opus 5 (1M context)"},
    "workspace": {"current_dir": "/tmp/fixture-project", "project_dir": "/tmp/fixture-project",
                  "added_dirs": []},
    "version": "2.1.276",
    "output_style": {"name": "default"},
    "cost": {"total_cost_usd": 3.21, "total_duration_ms": 812345, "total_api_duration_ms": 40000,
             "total_lines_added": 120, "total_lines_removed": 8},
    "context_window": {"total_input_tokens": 118432, "total_output_tokens": 1024,
                       "context_window_size": 1000000,
                       "current_usage": {"input_tokens": 4, "output_tokens": 1024,
                                         "cache_creation_input_tokens": 9310,
                                         "cache_read_input_tokens": 109118},
                       "used_percentage": 12, "remaining_percentage": 88},
    "exceeds_200k_tokens": False,
    "fast_mode": False,
    "thinking": {"enabled": True},
    "rate_limits": {"five_hour": {"used_percentage": 5.3, "resets_at": 1789700000},
                    "seven_day": {"used_percentage": 41.2, "resets_at": 1790200000}},
}

def w(name, text):
    with open(os.path.join(d, name), "w") as f:
        f.write(text)

w("normal", json.dumps(base))
w("empty", "")
w("not-json", "hello world\n")
w("truncated", json.dumps(base)[:120])

b = dict(base); del b["session_id"];                         w("no-session-id", json.dumps(b))
b = dict(base); b["session_id"] = "NOT-A-UUID";              w("bad-session-id", json.dumps(b))
b = dict(base); b["session_id"] = "../../../../etc/passwd-aaaaaaaaaaaaaaaaaaa"
w("traversal", json.dumps(b))
b = dict(base); b["workspace"] = {"current_dir": "/Users/x/專案 目錄", "project_dir": "/x"}
w("unicode", json.dumps(b, ensure_ascii=False))
w("pretty", json.dumps(base, indent=2) + "\n")
b = dict(base); b["filler"] = "x" * 200000;                  w("huge", json.dumps(b))
b = dict(base); b.pop("rate_limits"); b.pop("context_window")
w("minimal", json.dumps(b))
PY

# ── 對照執行 ─────────────────────────────────────────────────────
# $1 內層腳本  $2 快取目錄  $3 標籤
run_suite() {
  local inner="$1" cache="$2" label="$3" case_file name
  echo "▸ $label"
  for case_file in "$WORK"/cases/*; do
    name="$(basename "$case_file")"

    set +e
    QM_STATUSLINE_INNER="$inner" "$inner" < "$case_file" > "$WORK/d.out" 2> "$WORK/d.err"
    local drc=$?
    QM_STATUSLINE_INNER="$inner" QM_STATUSLINE_CACHE_DIR="$cache" \
      "$WRAPPER" < "$case_file" > "$WORK/w.out" 2> "$WORK/w.err"
    local wrc=$?
    set -e

    if cmp -s "$WORK/d.out" "$WORK/w.out" \
       && cmp -s "$WORK/d.err" "$WORK/w.err" \
       && [[ "$drc" == "$wrc" ]]; then
      PASS=$((PASS + 1))
      printf '  ✓ %-16s rc=%s stdout=%sB\n' "$name" "$drc" "$(wc -c < "$WORK/d.out" | tr -d ' ')"
    else
      FAIL=$((FAIL + 1))
      printf '  ✗ %-16s 直接跑 rc=%s / 經過 wrapper rc=%s\n' "$name" "$drc" "$wrc"
      diff <(cat -v "$WORK/d.out") <(cat -v "$WORK/w.out") | head -4 | sed 's/^/      stdout /' || true
      diff <(cat -v "$WORK/d.err") <(cat -v "$WORK/w.err") | head -4 | sed 's/^/      stderr /' || true
    fi
  done
}

run_suite "$WORK/stub-inner.sh" "$WORK/cache" "內層 = stub（回歸）"

# 快取路徑含空白 —— Application Support 底下一定會遇到
run_suite "$WORK/stub-inner.sh" "$WORK/App Support/QuotaMonster/statusline" \
          "內層 = stub、快取路徑含空白"

if [[ -x "$HOME/.claude/statusline.sh" ]]; then
  run_suite "$HOME/.claude/statusline.sh" "$WORK/cache-real" \
            "內層 = 使用者真正的 statusline.sh（驗收）"
else
  echo "▸ 跳過驗收輪：找不到 ~/.claude/statusline.sh"
fi

# ── 快取內容本身的斷言 ───────────────────────────────────────────
echo "▸ 快取內容"

assert() {
  if eval "$2"; then
    PASS=$((PASS + 1)); printf '  ✓ %s\n' "$1"
  else
    FAIL=$((FAIL + 1)); printf '  ✗ %s\n' "$1"
  fi
}

CACHE="$WORK/cache"
SID="11111111-1111-4111-8111-111111111111"

# 最後再明確餵一次，快取內容才不會取決於 glob 的順序
QM_STATUSLINE_INNER="$WORK/stub-inner.sh" QM_STATUSLINE_CACHE_DIR="$CACHE" \
  "$WRAPPER" < "$WORK/cases/huge" > /dev/null 2>&1

assert "payload 原文逐 byte 寫進 <session_id>.json" \
  "cmp -s '$WORK/cases/huge' '$CACHE/$SID.json'"
assert "快取檔權限是 0600" \
  "[[ \$(stat -f '%Lp' '$CACHE/$SID.json') == 600 ]]"
assert "沒有 session_id 的 payload 落到 _unkeyed.json" \
  "[[ -f '$CACHE/_unkeyed.json' ]]"
# wrapper 一定會加上 .json，所以只檢查不含副檔名的那個路徑是套套邏輯 —— 它本來就不會存在。
assert "路徑穿越沒有寫出快取目錄之外（含 wrapper 一定會加上的 .json）" \
  "[[ ! -e '$WORK/cache/../../../../etc/passwd-aaaaaaaaaaaaaaaaaaa' ]] \
   && [[ ! -e '$WORK/cache/../../../../etc/passwd-aaaaaaaaaaaaaaaaaaa.json' ]] \
   && [[ -z \$(ls -a '$CACHE' | grep passwd) ]]"
assert "沒有殘留 .tmp.* 檔（正常結束都該收乾淨）" \
  "[[ -z \$(find '$CACHE' -name '.tmp.*' -print -quit) ]]"

# umask 不可被 wrapper 汙染：內層建立的檔案要照呼叫端的 umask
cat > "$WORK/umask-inner.sh" <<'STUB'
#!/usr/bin/env bash
cat >/dev/null
umask
STUB
chmod +x "$WORK/umask-inner.sh"
GOT="$(umask 022; QM_STATUSLINE_INNER="$WORK/umask-inner.sh" \
       QM_STATUSLINE_CACHE_DIR="$WORK/cache-umask" "$WRAPPER" < "$WORK/cases/normal")"
assert "umask 在交棒給內層之前已還原（讀到 ${GOT}）" "[[ '${GOT}' == '0022' ]]"

# 遞迴保護：INNER 指向 wrapper 自己不可以變成 fork bomb。
# macOS 沒有 coreutils 的 timeout，所以自己看門：5 秒沒收工就強制殺掉並判定失敗。
set +e
QM_STATUSLINE_INNER="$WRAPPER" QM_STATUSLINE_CACHE_DIR="$WORK/cache-recur" \
  "$WRAPPER" < "$WORK/cases/normal" > "$WORK/recur.out" 2>&1 &
RPID=$!
for _ in $(seq 50); do
  kill -0 "$RPID" 2>/dev/null || break
  perl -e 'select(undef,undef,undef,0.1)'
done
if kill -0 "$RPID" 2>/dev/null; then
  pkill -9 -P "$RPID" 2>/dev/null
  kill -9 "$RPID" 2>/dev/null
  RRC=timeout
else
  wait "$RPID"; RRC=$?
fi
set -e
assert "INNER 指向自己時立刻收手，不 fork bomb（rc=${RRC}）" \
  "[[ '${RRC}' == '0' ]] && grep -q 'points at the wrapper itself' '${WORK}/recur.out'"

# ── 退化環境：快取壞掉也絕不可以影響狀態列 ───────────────────────
# 官方文件：離開碼非 0 或輸出為空 → 狀態列整條變空白。
# 所以「快取寫不進去」必須表現得跟「沒有 wrapper」一模一樣。
# 這一整段是 code review 抓到 CRITICAL 之後補的：實測快取目錄不可寫時，
# wrapper 會以 rc=1、零輸出收工，使用者的狀態列整條不見。
echo "▸ 快取寫不進去時仍然逐 byte 相同"

degraded() {
  local label="$1" cache="$2"
  set +e
  "$WORK/stub-inner.sh" < "$WORK/cases/normal" > "$WORK/d.out" 2> "$WORK/d.err"
  local drc=$?
  QM_STATUSLINE_INNER="$WORK/stub-inner.sh" QM_STATUSLINE_CACHE_DIR="$cache" \
    "$WRAPPER" < "$WORK/cases/normal" > "$WORK/w.out" 2> "$WORK/w.err"
  local wrc=$?
  set -e
  if cmp -s "$WORK/d.out" "$WORK/w.out" && [[ "$drc" == "$wrc" ]] && [[ -s "$WORK/w.out" ]]; then
    PASS=$((PASS + 1)); printf '  ✓ %s\n' "$label"
  else
    FAIL=$((FAIL + 1))
    printf '  ✗ %s — rc %s vs %s，wrapper stdout %s bytes\n' \
      "$label" "$drc" "$wrc" "$(wc -c < "$WORK/w.out" | tr -d ' ')"
  fi
}

RO="$WORK/readonly"; mkdir -p "$RO"; chmod 555 "$RO"
degraded "快取目錄不可寫" "$RO"
chmod 755 "$RO"

ROP="$WORK/readonly-parent"; mkdir -p "$ROP"; chmod 555 "$ROP"
degraded "快取目錄的上層不可寫（mkdir 會失敗）" "$ROP/sub"
chmod 755 "$ROP"

touch "$WORK/not-a-dir"
degraded "快取路徑是一個檔案而不是目錄" "$WORK/not-a-dir"

# 第一次渲染時 umask 很嚴：建出來的目錄不可以變成永久不可寫
UM="$WORK/umask-dir"
( umask 0222
  QM_STATUSLINE_INNER="$WORK/stub-inner.sh" QM_STATUSLINE_CACHE_DIR="$UM" \
    "$WRAPPER" < "$WORK/cases/normal" >/dev/null 2>&1 ) || true
assert "嚴格 umask 下第一次渲染仍然寫得出快取" \
  "[[ -n \$(ls -A '$UM' 2>/dev/null) ]]"
degraded "嚴格 umask 下建立的快取目錄，之後仍然寫得進去" "$UM"

# ── 訊號：中止時不可以留下垃圾，也不可以毀掉上一筆好的快取 ───────
echo "▸ 訊號"

SIGDIR="$WORK/sig"; mkdir -p "$SIGDIR"
SID_GOOD="11111111-1111-4111-8111-111111111111"
printf '%s' "{\"session_id\":\"$SID_GOOD\",\"good\":1}" > "$WORK/good.json"
QM_STATUSLINE_INNER="$WORK/stub-inner.sh" QM_STATUSLINE_CACHE_DIR="$SIGDIR" \
  "$WRAPPER" < "$WORK/good.json" >/dev/null 2>&1
GOOD_BEFORE="$(cat "$SIGDIR/$SID_GOOD.json" 2>/dev/null || echo MISSING)"

# 用大括號群組把 bash 的工作狀態通知（"Terminated: 15"）吞掉。
# 大括號不開子 shell，所以裡面設定的變數留得住。
{
mkfifo "$WORK/fifo"
QM_STATUSLINE_INNER="$WORK/stub-inner.sh" QM_STATUSLINE_CACHE_DIR="$SIGDIR" \
  "$WRAPPER" < "$WORK/fifo" >/dev/null 2>&1 &
SIGPID=$!
exec 9> "$WORK/fifo"
printf '{"session_id":"%s","partial":' "$SID_GOOD" >&9
perl -e 'select(undef,undef,undef,0.3)'
kill -TERM "$SIGPID" 2>/dev/null || true

# 看門狗：收到 SIGTERM 之後必須真的收工。trap 只做 rm 卻不 exit 的話，
# cat 會回頭繼續等 stdin，這個 wait 會永遠卡住 —— 測試要判定失敗，不是掛住。
SIG_EXITED=0
for _ in $(seq 30); do
  kill -0 "$SIGPID" 2>/dev/null || { SIG_EXITED=1; break; }
  perl -e 'select(undef,undef,undef,0.1)'
done
if (( SIG_EXITED == 0 )); then
  kill -KILL "$SIGPID" 2>/dev/null || true
fi
exec 9>&-
wait "$SIGPID" 2>/dev/null || true
rm -f "$WORK/fifo"
} 2>/dev/null

# ⚠️ 這一則**不是 trap 的覆蓋率**。〔實測 2026-09-21〕把 wrapper 第 55-57 行三個
#    trap 全部刪掉，這一則照樣通過 —— 因為 TERM 是在那個阻塞的 `read` 期間送到的，
#    那時 trap 還沒安裝，收工靠的是預設處置。它證明的只是「不會掛住」。
#    真正會用到 trap 的窗口（read 完成之後、交棒之前的那幾毫秒）沒有辦法穩定命中。
assert "收到 SIGTERM 之後 3 秒內收工（證明的是「不會掛住」，不是 trap 有效）" \
  "[[ ${SIG_EXITED} -eq 1 ]]"
assert "SIGTERM 之後上一筆完整的快取沒有被動到" \
  "[[ \"\$(cat '$SIGDIR/$SID_GOOD.json' 2>/dev/null)\" == '$GOOD_BEFORE' ]]"
assert "SIGTERM 之後沒有留下 .tmp.* 垃圾" \
  "[[ -z \$(find '$SIGDIR' -name '.tmp.*' -print -quit) ]]"

# ── 語系：非 UTF-8 的 byte 不可以讓 session_id 抽取失敗 ───────────
echo "▸ 語系"
LOCDIR="$WORK/locale"; mkdir -p "$LOCDIR"
printf '{"cwd":"/tmp/\xff\xfe","session_id":"%s","x":1}' "$SID_GOOD" > "$WORK/badutf8.json"
LC_ALL=zh_TW.UTF-8 QM_STATUSLINE_INNER="$WORK/stub-inner.sh" \
  QM_STATUSLINE_CACHE_DIR="$LOCDIR" "$WRAPPER" < "$WORK/badutf8.json" >/dev/null 2>&1 || true
assert "payload 前段有非 UTF-8 byte 時，session_id 仍然抽得出來" \
  "[[ -f '$LOCDIR/$SID_GOOD.json' ]]"

# ── 原子寫入：讀取端絕不可以看到寫一半的 JSON ───────────────────
# Claude Code 會在新事件觸發時 abort 執行中的腳本，所以「寫一半」不是理論問題。
# 這是 wrapper 的招牌保證之一，之前只在 scratchpad 驗過，沒有進測試。
echo "▸ 原子寫入"

ATOMIC="$WORK/atomic"; mkdir -p "$ATOMIC"

cat > "$WORK/reader.py" <<'READER'
import glob, json, os, sys, time
d = sys.argv[1]
deadline = time.time() + float(sys.argv[2])
ok = torn = 0
while time.time() < deadline:
    for f in glob.glob(os.path.join(d, "*.json")):
        try:
            json.load(open(f))
            ok += 1
        except Exception as e:
            torn += 1
            print("TORN", os.path.basename(f), e)
print("PARSES", ok, "TORN_TOTAL", torn)
READER

python3 "$WORK/reader.py" "$ATOMIC" 6 > "$WORK/reader.txt" 2>&1 &
READER_PID=$!

PAD="$(printf 'x%.0s' $(seq 400))"
for sid in 11111111-1111-4111-8111-111111111111 \
           22222222-2222-4222-8222-222222222222 \
           33333333-3333-4333-8333-333333333333; do
  for _w in 1 2; do
    (
      for i in $(seq 12); do
        printf '{"session_id":"%s","n":%s,"pad":"%s"}' "$sid" "$i" "$PAD" |
          QM_STATUSLINE_INNER="$WORK/stub-inner.sh" QM_STATUSLINE_CACHE_DIR="$ATOMIC" \
            "$WRAPPER" >/dev/null 2>&1
      done
    ) &
  done
done
wait
wait "$READER_PID" 2>/dev/null || true

TORN="$(awk '/^PARSES/ {print $4}' "$WORK/reader.txt")"
PARSES="$(awk '/^PARSES/ {print $2}' "$WORK/reader.txt")"
assert "多個寫入者同時渲染時讀取端沒有讀到半個檔（${PARSES:-0} 次解析、${TORN:-?} 次撕裂）" \
  "[[ '${TORN:-1}' == '0' && ${PARSES:-0} -gt 0 ]]"
assert "三個 session 各自留下一份完整的快取" \
  "[[ \$(ls '$ATOMIC'/*.json 2>/dev/null | wc -l | tr -d ' ') -eq 3 ]]"

# ── 空 payload 不可以蓋掉上一筆好的快取 ─────────────────────────
echo "▸ 空 payload"
EMPTYD="$WORK/emptyguard"; mkdir -p "$EMPTYD"
SID_E="11111111-1111-4111-8111-111111111111"
printf '{"session_id":"%s","good":1}' "$SID_E" > "$WORK/e_good.json"
QM_STATUSLINE_INNER="$WORK/stub-inner.sh" QM_STATUSLINE_CACHE_DIR="$EMPTYD" \
  "$WRAPPER" < "$WORK/e_good.json" >/dev/null 2>&1
E_BEFORE="$(cat "$EMPTYD/$SID_E.json")"
set +e
QM_STATUSLINE_INNER="$WORK/stub-inner.sh" QM_STATUSLINE_CACHE_DIR="$EMPTYD" \
  "$WRAPPER" < /dev/null >/dev/null 2>&1
set -e
assert "空的 stdin 不會蓋掉上一筆好的快取" \
  "[[ \"\$(cat '$EMPTYD/$SID_E.json')\" == '$E_BEFORE' ]]"
assert "空的 stdin 不會生出 _unkeyed.json 垃圾" \
  "[[ ! -e '$EMPTYD/_unkeyed.json' ]]"

# ── 裸 NUL：截斷的 payload 不可以蓋掉上一筆好的快取 ──────────────
# 為什麼要測這個：`IFS= read -r -d ''` 讀到 NUL 就停，NUL 之後的 byte 全部消失。
# 〔實測 2026-09-21〕72 byte 的 payload 餵進去，內層只收到 59 byte、快取檔也只有
# 59 byte，而且那份截斷版**經 rename 蓋掉了上一筆完整的快取**（`[ -s ]` 只檢查
# 非空，不檢查完整），該 session 的讀數整個不見。
#
# wrapper 的檔頭推論「JSON.stringify 不可能送出裸 NUL」——〔推論，非實測〕
# 那大概是對的，但代價不對稱：猜錯一次就是安靜地毀掉快取。
echo "▸ 裸 NUL"
NULDIR="$WORK/nul"; mkdir -p "$NULDIR"
printf '{"session_id":"%s","good":true}' "$SID_GOOD" > "$NULDIR/$SID_GOOD.json"
NUL_BEFORE="$(cat "$NULDIR/$SID_GOOD.json")"
printf '{"session_id":"%s","a":"X\000Y","tail":1}' "$SID_GOOD" \
  | QM_STATUSLINE_INNER="$WORK/stub-inner.sh" QM_STATUSLINE_CACHE_DIR="$NULDIR" \
    "$WRAPPER" >/dev/null 2>&1 || true
assert "payload 含裸 NUL 時，上一筆完整的快取不可以被截斷版蓋掉" \
  "[[ \"\$(cat '$NULDIR/$SID_GOOD.json' 2>/dev/null)\" == '$NUL_BEFORE' ]]"
assert "含裸 NUL 時也不留下 .tmp.* 垃圾" \
  "[[ -z \$(find '$NULDIR' -name '.tmp.*' -print -quit) ]]"

# ── 內層不可執行時，狀態列不可以整條消失 ──────────────────────────
# 〔實測〕INNER 指到不存在的檔 → rc=127、stdout 0 byte；INNER 是 0644 → rc=126、
# stdout 0 byte。官方文件：離開碼非 0 或輸出為空 → 狀態列整條變空白。
# 這與這支腳本檔頭寫的唯一承諾直接衝突。
echo "▸ 內層不可執行"
BADIN="$WORK/badinner"; mkdir -p "$BADIN"
# ⚠️ 這裡要關掉 errexit：wrapper 現在回非 0 的話，賦值本身就會讓這支腳本中止，
#    於是「它回了非 0」這件事變成測試崩潰而不是測試失敗。
set +e
OUT_MISSING="$(printf '{"session_id":"%s"}' "$SID_GOOD" \
  | QM_STATUSLINE_INNER="$BADIN/does-not-exist.sh" QM_STATUSLINE_CACHE_DIR="$BADIN" \
    "$WRAPPER" 2>/dev/null)"
RC_MISSING=$?
printf '#!/bin/sh\necho hi\n' > "$BADIN/notexec.sh"; chmod 0644 "$BADIN/notexec.sh"
OUT_NOEXEC="$(printf '{"session_id":"%s"}' "$SID_GOOD" \
  | QM_STATUSLINE_INNER="$BADIN/notexec.sh" QM_STATUSLINE_CACHE_DIR="$BADIN" \
    "$WRAPPER" 2>/dev/null)"
RC_NOEXEC=$?
set -e
assert "內層不存在時 stdout 不可以是空的（否則狀態列整條消失）" \
  "[[ -n \"\$OUT_MISSING\" ]]"
assert "內層不存在時離開碼要是 0" "[[ ${RC_MISSING} -eq 0 ]]"
assert "內層不可執行時 stdout 不可以是空的" "[[ -n \"\$OUT_NOEXEC\" ]]"
assert "內層不可執行時離開碼要是 0" "[[ ${RC_NOEXEC} -eq 0 ]]"

# ── shadow 量測：預設不做，設了才做 ──────────────────────────────
echo "▸ shadow 量測"
TRD="$WORK/trace"; mkdir -p "$TRD"
printf '{"session_id":"%s","rate_limits":{"five_hour":{"used_percentage":22,"resets_at":1790002200}}}' \
  "$SID_GOOD" > "$WORK/trace-payload.json"
QM_STATUSLINE_INNER="$WORK/stub-inner.sh" QM_STATUSLINE_CACHE_DIR="$TRD" \
  "$WRAPPER" < "$WORK/trace-payload.json" >/dev/null 2>&1 || true
assert "沒設 QM_STATUSLINE_TRACE 時一個 byte 都不寫" \
  "[[ -z \$(find '$TRD' -name '*.log' -print -quit) ]]"

for _ in 1 2 3; do
  QM_STATUSLINE_TRACE="$TRD/t.log" QM_STATUSLINE_INNER="$WORK/stub-inner.sh" \
    QM_STATUSLINE_CACHE_DIR="$TRD" "$WRAPPER" < "$WORK/trace-payload.json" >/dev/null 2>&1 || true
done
assert "設了之後每一次渲染記一行（三次 → 三行）" \
  "[[ \$(wc -l < '$TRD/t.log') -eq 3 ]]"
assert "記下來的是 rate_limits 原文" "grep -q 'used_percentage\":22' '$TRD/t.log'"
assert "每一行都帶 epoch 時間戳" "grep -qE '^[0-9]{10}\s' '$TRD/t.log'"

# 量測不可以把狀態列弄不見 —— log 路徑寫不進去時，輸出仍然必須逐 byte 相同
"$WORK/stub-inner.sh" < "$WORK/trace-payload.json" > "$WORK/trace-expect.out" 2>/dev/null || true
QM_STATUSLINE_TRACE="$TRD/no-such-dir/t.log" QM_STATUSLINE_INNER="$WORK/stub-inner.sh" \
  QM_STATUSLINE_CACHE_DIR="$TRD" "$WRAPPER" < "$WORK/trace-payload.json" \
  > "$WORK/trace-got.out" 2>/dev/null || true
assert "log 寫不進去時，狀態列輸出仍然逐 byte 相同" \
  "cmp -s '$WORK/trace-expect.out' '$WORK/trace-got.out'"

# 開關檔：不改 settings.json 就能開關
SWD="$WORK/switch/statusline"; mkdir -p "$SWD"
QM_STATUSLINE_INNER="$WORK/stub-inner.sh" QM_STATUSLINE_CACHE_DIR="$SWD" \
  "$WRAPPER" < "$WORK/trace-payload.json" >/dev/null 2>&1 || true
assert "沒有開關檔就不記" "[[ ! -e '$WORK/switch/trace-usage.log' ]]"
touch "$WORK/switch/trace-usage.on"
QM_STATUSLINE_INNER="$WORK/stub-inner.sh" QM_STATUSLINE_CACHE_DIR="$SWD" \
  "$WRAPPER" < "$WORK/trace-payload.json" >/dev/null 2>&1 || true
assert "有開關檔就開始記，而且不需要任何環境變數" \
  "[[ -s '$WORK/switch/trace-usage.log' ]]"
rm -f "$WORK/switch/trace-usage.on"
LINES_AFTER_OFF="$(wc -l < "$WORK/switch/trace-usage.log")"
QM_STATUSLINE_INNER="$WORK/stub-inner.sh" QM_STATUSLINE_CACHE_DIR="$SWD" \
  "$WRAPPER" < "$WORK/trace-payload.json" >/dev/null 2>&1 || true
assert "刪掉開關檔就停下來（關掉也不用動設定）" \
  "[[ \$(wc -l < '$WORK/switch/trace-usage.log') -eq ${LINES_AFTER_OFF} ]]"

# ── 沒有內層時，wrapper 自己印一行 ──────────────────────────────
# 為什麼要有這條路：〔實測 2026-09-21〕`~/.claude.json` 的額度欄位已經不再更新
# （檔案一直被重寫，但 fetchedAtMs 凍了 3.9 天），所以**沒有 tee 就沒有額度數字**。
# 而安裝腳本原本要求使用者已經有自訂 statusLine —— 沒有的人（多數新使用者）
# 連裝都裝不了。現在「沒有內層」是一條合法的路，不是錯誤。
#
# ⚠️ 與「內層設了但壞掉」必須分得開：那個仍然要報錯（它代表設定壞了）。
echo "▸ 沒有內層"
NOIN="$WORK/noinner"; mkdir -p "$NOIN"
printf '%s' '{"session_id":"11111111-1111-4111-8111-111111111111","model":{"display_name":"Opus 5 (1M context)"},"context_window":{"used_percentage":26},"rate_limits":{"five_hour":{"used_percentage":31},"seven_day":{"used_percentage":15}}}' \
  > "$WORK/full-payload.json"
set +e
OUT_BUILTIN="$(QM_STATUSLINE_CACHE_DIR="$NOIN" "$WRAPPER" < "$WORK/full-payload.json" 2>/dev/null)"
RC_BUILTIN=$?
set -e
assert "沒設內層時 stdout 不可以是空的（否則狀態列整條消失）" "[[ -n \"\$OUT_BUILTIN\" ]]"
assert "沒設內層時離開碼 0" "[[ ${RC_BUILTIN} -eq 0 ]]"
assert "內建那一行帶得出模型" "[[ \"\$OUT_BUILTIN\" == *'Opus 5'* ]]"
assert "內建那一行帶得出 context 壓力" "[[ \"\$OUT_BUILTIN\" == *'ctx 26%'* ]]"
assert "內建那一行帶得出 5 小時額度" "[[ \"\$OUT_BUILTIN\" == *'5h 31%'* ]]"
assert "內建那一行帶得出 7 天額度" "[[ \"\$OUT_BUILTIN\" == *'7d 15%'* ]]"
assert "沒設內層時快取照樣寫" "[[ -f '$NOIN/11111111-1111-4111-8111-111111111111.json' ]]"

# 欄位缺席時不可以印出空的欄位或「%」孤兒
printf '%s' '{"session_id":"11111111-1111-4111-8111-111111111111","model":{"display_name":"Haiku"}}' \
  > "$WORK/thin-payload.json"
set +e
OUT_THIN="$(QM_STATUSLINE_CACHE_DIR="$NOIN" "$WRAPPER" < "$WORK/thin-payload.json" 2>/dev/null)"
set -e
assert "payload 只有模型時仍然印得出東西" "[[ -n \"\$OUT_THIN\" ]]"
assert "缺席的欄位整個不出現，不會留下孤兒的 %" "[[ \"\$OUT_THIN\" != *'%'* ]]"

# ⚠️ 這條不可以被上面那條蓋掉：內層**設了但壞掉**仍然要講出來
set +e
OUT_BROKEN="$(QM_STATUSLINE_INNER="$NOIN/nope.sh" QM_STATUSLINE_CACHE_DIR="$NOIN" \
  "$WRAPPER" < "$WORK/full-payload.json" 2>/dev/null)"
set -e
assert "內層設了但不存在時，講的是錯誤而不是內建那一行" \
  "[[ \"\$OUT_BROKEN\" == *'不可執行'* ]]"

# ── shadow log 的輪替 ───────────────────────────────────────────
# ⚠️ 這支 log 每次渲染寫一行，而且是 **bash 在 append**，所以清理不能交給 app
#（app 用 tmp + rename 換檔，會把正在寫的那一行丟掉，而且兩個寫入者搶同一個檔）。
# 由 wrapper 自己在寫之前看一眼大小，超過就砍掉前半。
echo "▸ shadow log 輪替"
ROTD="$WORK/rot"; mkdir -p "$ROTD"
ROTLOG="$ROTD/t.log"
# 造一個超過上限的檔案
uv_python=$(command -v python3)
"$uv_python" - "$ROTLOG" <<'PYEOF'
import sys
open(sys.argv[1],'w').write('x'*(1200*1024) + '\n')
PYEOF
BEFORE=$(wc -c < "$ROTLOG" | tr -d ' ')
QM_STATUSLINE_TRACE="$ROTLOG" QM_STATUSLINE_INNER="$WORK/stub-inner.sh" \
  QM_STATUSLINE_CACHE_DIR="$ROTD" "$WRAPPER" < "$WORK/trace-payload.json" >/dev/null 2>&1 || true
AFTER=$(wc -c < "$ROTLOG" | tr -d ' ')
assert "超過上限時會砍掉前半（${BEFORE} → ${AFTER}）" "[[ ${AFTER} -lt ${BEFORE} ]]"
assert "砍完之後仍然在上限之內" "[[ ${AFTER} -le 1048576 ]]"
assert "砍完之後新的那一行還是寫得進去" "grep -q 'used_percentage' '$ROTLOG'"

# ⚠️ 沒超過上限時**不可以重寫整個檔**。
#    比對內容分不出來：`tail -c 512K` 對一個小檔不會損壞任何東西，
#    所以「一律砍」這個突變在內容比對上照樣過（實測紅 0 則）。
#    差別在**有沒有重寫**，而那要用 inode 量 —— 與安裝腳本那則同一招。
SMALL="$ROTD/small.log"; printf 'keep-me\n' > "$SMALL"
SMALL_INO_BEFORE=$(stat -f%i "$SMALL")
QM_STATUSLINE_TRACE="$SMALL" QM_STATUSLINE_INNER="$WORK/stub-inner.sh" \
  QM_STATUSLINE_CACHE_DIR="$ROTD" "$WRAPPER" < "$WORK/trace-payload.json" >/dev/null 2>&1 || true
assert "沒超過上限時舊內容原封不動" "head -1 '$SMALL' | grep -q 'keep-me'"
assert "沒超過上限時不重寫整個檔（inode 不變）" \
  "[[ ${SMALL_INO_BEFORE} == \$(stat -f%i '$SMALL') ]]"

# ── 結果 ─────────────────────────────────────────────────────────
echo
REACHED_END=1
if (( FAIL == 0 )); then
  echo "✓ ${PASS} 項全數通過"
else
  echo "✗ ${FAIL} 項失敗（通過 ${PASS} 項）" >&2
  exit 1
fi
