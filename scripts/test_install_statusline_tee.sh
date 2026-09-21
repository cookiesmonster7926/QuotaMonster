#!/usr/bin/env bash
# 為什麼需要這支腳本：
# 安裝腳本會改使用者的 ~/.claude/settings.json。那個檔裡面有 hooks、plugin 設定、
# 主題…，改壞了不是「功能沒生效」，是使用者的環境壞掉。
# 所以安裝腳本的每一條保證都要被測到，而且測試絕不可以碰真的 ~/.claude ——
# 全部跑在 QM_CLAUDE_DIR 指向的暫時目錄上。
#
# 被釘住的保證：
#   1. 只有 statusLine.command 這一個字串會變，其餘 byte 完全不動
#   2. 動之前一定留下備份，且備份與原檔逐 byte 相同
#   3. 改出來的命令真的能跑，且輸出與原本的狀態列腳本逐 byte 相同
#   4. 可重複執行（第二次不會再包一層）
#   5. --uninstall 還原成原本的 byte
#   6. 不帶 --apply 時什麼都不改
#   7. 看不懂的設定一律拒絕動手，而不是猜
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="$ROOT/scripts/install_statusline_tee.sh"

if [[ ! -x "$INSTALLER" ]]; then
  echo "✗ 找不到可執行的安裝腳本：$INSTALLER" >&2
  exit 1
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/qm-install-test.XXXXXX")"
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
assert() {
  if eval "$2"; then
    PASS=$((PASS + 1)); printf '  ✓ %s\n' "$1"
  else
    FAIL=$((FAIL + 1)); printf '  ✗ %s\n' "$1"
  fi
}

# ── 假的 ~/.claude ───────────────────────────────────────────────
# 刻意做得跟使用者真正的設定一樣雜：前面有 hooks、後面有 plugin 設定，
# 這樣「只動一個字串」才是有意義的斷言。
make_claude_dir() {
  local dir="$1" command_value="$2"
  rm -rf "$dir"; mkdir -p "$dir"
  cat > "$dir/settings.json" <<EOF
{
  "model": "opus[1m]",
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "python3 ${dir}/hooks/block_no_verify.py"
          }
        ]
      }
    ]
  },
  "statusLine": {
    "type": "command",
    "command": "${command_value}"
  },
  "effortLevel": "xhigh",
  "theme": "dark"
}
EOF
  cat > "$dir/statusline.sh" <<'INNER'
#!/usr/bin/env bash
set -euo pipefail
input=$(cat)
printf '\033[36m%s bytes\033[0m\n\033[90mline two\033[0m' "${#input}"
INNER
  chmod +x "$dir/statusline.sh"
}

PAYLOAD="$WORK/payload.json"
printf '%s' '{"session_id":"11111111-1111-4111-8111-111111111111","cwd":"/tmp","version":"2.1.276"}' \
  > "$PAYLOAD"

# ── 1. 預設不套用 ────────────────────────────────────────────────
echo "▸ 不帶 --apply 時只印 diff，不動任何東西"
# ⚠️ 這一則刻意餵 `$HOME/...` 形式的命令（安裝腳本會把家目錄底下的路徑寫成
#    "$HOME/..."，所以它必須看得懂這個形式）。
#    **但不可以指向開發者真正的 ~/.claude/statusline.sh** ——
#    〔實測 2026-09-21，GitHub Actions 第一次跑〕runner 上沒有那個檔，
#    安裝腳本判定「命令不是可執行檔」而拒絕，這一則就紅了。
#    開發機上永遠看不到，因為開發機**剛好有**那個檔。
#    所以自己造一個假的 HOME，`$HOME` 展開的語意照測，環境依賴拿掉。
D="$WORK/dry"; make_claude_dir "$D" '$HOME/.claude/statusline.sh'
FAKEHOME="$WORK/fakehome"; mkdir -p "$FAKEHOME/.claude"
cp "$D/statusline.sh" "$FAKEHOME/.claude/statusline.sh"
chmod +x "$FAKEHOME/.claude/statusline.sh"
cp "$D/settings.json" "$WORK/dry.before"
set +e
HOME="$FAKEHOME" QM_CLAUDE_DIR="$D" "$INSTALLER" > "$WORK/dry.out" 2>&1
DRY_RC=$?
set -e
assert "離開碼 0" "[[ ${DRY_RC} -eq 0 ]]"
assert "settings.json 一個 byte 都沒變" "cmp -s '$WORK/dry.before' '$D/settings.json'"
assert "沒有安裝 wrapper" "[[ ! -e '$D/quotamonster-tee.sh' ]]"
assert "沒有留下備份" "[[ -z \$(find '$D' -name 'settings.json.bak-*' -print -quit) ]]"
assert "有把 diff 印出來" "grep -q 'statusLine' '$WORK/dry.out'"

# ── 2. 實際安裝 ──────────────────────────────────────────────────
echo "▸ --apply 安裝"
A="$WORK/apply"; make_claude_dir "$A" "$WORK/apply/statusline.sh"
cp "$A/settings.json" "$WORK/apply.before"
set +e
QM_CLAUDE_DIR="$A" "$INSTALLER" --apply > "$WORK/apply.out" 2>&1
APPLY_RC=$?
set -e
assert "離開碼 0" "[[ ${APPLY_RC} -eq 0 ]]"
assert "wrapper 已安裝且可執行" "[[ -x '$A/quotamonster-tee.sh' ]]"
assert "wrapper 與 repo 裡的那份逐 byte 相同" \
  "cmp -s '$ROOT/scripts/quotamonster-tee.sh' '$A/quotamonster-tee.sh'"

BACKUP="$(find "$A" -name 'settings.json.bak-*' | head -1)"
assert "留下了備份" "[[ -n '$BACKUP' ]]"
assert "備份與動手前的原檔逐 byte 相同" "cmp -s '$WORK/apply.before' '$BACKUP'"

# 只有 command 那個字串變了 —— 把新值換回舊值，必須得到原本的 byte
python3 - "$WORK/apply.before" "$A/settings.json" > "$WORK/onlycmd.txt" <<'PY'
import json, sys
before_raw = open(sys.argv[1]).read()
after_raw  = open(sys.argv[2]).read()
before = json.loads(before_raw)
after  = json.loads(after_raw)
old_cmd = before["statusLine"]["command"]
new_cmd = after["statusLine"]["command"]
restored = after_raw.replace(json.dumps(new_cmd), json.dumps(old_cmd))
b2 = dict(before); a2 = dict(after)
b2["statusLine"] = dict(b2["statusLine"]); a2["statusLine"] = dict(a2["statusLine"])
b2["statusLine"].pop("command"); a2["statusLine"].pop("command")
print("BYTES_RESTORE_OK" if restored == before_raw else "BYTES_RESTORE_FAIL")
print("REST_OF_TREE_OK" if b2 == a2 else "REST_OF_TREE_FAIL")
print("COMMAND_CHANGED_OK" if old_cmd != new_cmd else "COMMAND_CHANGED_FAIL")
PY
assert "把 command 換回舊值就得到原本的 byte（其餘完全沒動）" \
  "grep -q BYTES_RESTORE_OK '$WORK/onlycmd.txt'"
assert "除了 command 之外整棵設定樹相同" "grep -q REST_OF_TREE_OK '$WORK/onlycmd.txt'"
assert "command 確實被改掉了" "grep -q COMMAND_CHANGED_OK '$WORK/onlycmd.txt'"

# ── 3. 改出來的命令真的能跑，而且輸出不變 ────────────────────────
echo "▸ 安裝後的命令跑起來與原本逐 byte 相同"
NEW_CMD="$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['statusLine']['command'])" "$A/settings.json")"
"$A/statusline.sh" < "$PAYLOAD" > "$WORK/expect.out" 2> "$WORK/expect.err"; EXP_RC=$?
set +e
( cd /tmp && QM_STATUSLINE_CACHE_DIR="$A/cache" /bin/sh -c "$NEW_CMD" < "$PAYLOAD" \
    > "$WORK/got.out" 2> "$WORK/got.err" )
GOT_RC=$?
set -e
assert "stdout 相同" "cmp -s '$WORK/expect.out' '$WORK/got.out'"
assert "stderr 相同" "cmp -s '$WORK/expect.err' '$WORK/got.err'"
assert "離開碼相同" "[[ ${EXP_RC} -eq ${GOT_RC} ]]"
assert "payload 真的被快取起來了" \
  "cmp -s '$PAYLOAD' '$A/cache/11111111-1111-4111-8111-111111111111.json'"

# ── 4. 可重複執行 ────────────────────────────────────────────────
echo "▸ 再跑一次不會包第二層"
cp "$A/settings.json" "$WORK/apply.once"
set +e
QM_CLAUDE_DIR="$A" "$INSTALLER" --apply > "$WORK/apply2.out" 2>&1
RC2=$?
set -e
assert "離開碼 0" "[[ ${RC2} -eq 0 ]]"
assert "settings.json 沒有再變" "cmp -s '$WORK/apply.once' '$A/settings.json'"

# ── 5. 解除安裝 ──────────────────────────────────────────────────
echo "▸ --uninstall 還原"
set +e
QM_CLAUDE_DIR="$A" "$INSTALLER" --uninstall --apply > "$WORK/un.out" 2>&1
UN_RC=$?
set -e
assert "離開碼 0" "[[ ${UN_RC} -eq 0 ]]"
assert "settings.json 還原成原本的 byte" "cmp -s '$WORK/apply.before' '$A/settings.json'"
assert "wrapper 已移除" "[[ ! -e '$A/quotamonster-tee.sh' ]]"

# ── 6. 看不懂的設定要拒絕 ────────────────────────────────────────
echo "▸ 拒絕動手的情況"

R1="$WORK/no-statusline"; make_claude_dir "$R1" 'x'
python3 - "$R1/settings.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
del d["statusLine"]
open(p, "w").write(json.dumps(d, indent=2) + "\n")
PY
cp "$R1/settings.json" "$WORK/r1.before"
set +e; QM_CLAUDE_DIR="$R1" "$INSTALLER" --apply > "$WORK/r1.out" 2>&1; R1RC=$?; set -e
# ⚠️ 這裡的行為在 2026-09-21 改了，而且是**刻意**改的。
#    原本：沒有 statusLine 就拒絕（「不猜」）。
#    現在：沒有 statusLine 就**幫忙建一個**（wrapper 自己會印一行最小狀態列）。
#    為什麼不算違反「不猜」：沒有東西可以保留，就沒有東西會被猜壞。
#    那條規矩擋的是「看不懂既有的設定卻硬要包」，不是「從零建立」。
#    為什麼非改不可：〔實測〕~/.claude.json 的額度欄位已經不再更新，
#    所以沒有 tee 就沒有額度數字 —— 而多數新使用者沒有自訂 statusLine，
#    原本的拒絕等於把他們擋在門外。
assert "沒有 statusLine 設定時改成幫忙建一個（離開碼 0）" "[[ ${R1RC} -eq 0 ]]"
assert "建出來的 command 走 tee" "grep -q 'quotamonster-tee.sh' '$R1/settings.json'"
assert "建出來的 command type 是 command" \
  "python3 -c \"import json;d=json.load(open('$R1/settings.json'));import sys;sys.exit(0 if d['statusLine']['type']=='command' else 1)\""
assert "建出來的那條命令真的跑得出非空輸出" \
  "[[ -n \$(printf '%s' '{\"session_id\":\"11111111-1111-4111-8111-111111111111\",\"model\":{\"display_name\":\"X\"}}' | QM_STATUSLINE_CACHE_DIR='$R1/cache' bash '$R1/quotamonster-tee.sh') ]]"
assert "從零建立時也留下備份" "[[ -n \$(find '$R1' -name 'settings.json.bak-*' -print -quit) ]]"
# ⚠️ 只有「從零建立」放行。**看不懂既有的設定仍然要拒絕** —— 下面幾則守著。
assert "從零建立之後，settings.json 其餘部分沒有被動到" \
  "python3 -c \"import json;a=json.load(open('$WORK/r1.before'));b=json.load(open('$R1/settings.json'));b.pop('statusLine');import sys;sys.exit(0 if a==b else 1)\""

# ⚠️ 從零建立之後的 --uninstall 必須把**整個 statusLine 拿掉**，
#    不是把 command 還原成空字串 —— 那會留下一個 command 是 "" 的 statusLine，
#    Claude Code 會拿空命令去跑，狀態列整條變空白。
QM_CLAUDE_DIR="$R1" "$INSTALLER" --uninstall --apply > "$WORK/r1.un.out" 2>&1
assert "從零建立之後 --uninstall 把整個 statusLine 拿掉" \
  "python3 -c \"import json;d=json.load(open('$R1/settings.json'));import sys;sys.exit(0 if 'statusLine' not in d else 1)\""
assert "從零建立之後 --uninstall 還原成原本的 byte" "cmp -s '$WORK/r1.before' '$R1/settings.json'"
assert "從零建立之後 --uninstall 也移除 wrapper" "[[ ! -e '$R1/quotamonster-tee.sh' ]]"

R2="$WORK/not-a-file"; make_claude_dir "$R2" 'npx ccstatusline@latest --fancy'
cp "$R2/settings.json" "$WORK/r2.before"
set +e; QM_CLAUDE_DIR="$R2" "$INSTALLER" --apply > "$WORK/r2.out" 2>&1; R2RC=$?; set -e
assert "原本的命令不是可執行檔時拒絕（不猜）" "[[ ${R2RC} -ne 0 ]]"
assert "拒絕時不動 settings.json" "cmp -s '$WORK/r2.before' '$R2/settings.json'"
assert "拒絕時說得出原因" "grep -q 'ccstatusline' '$WORK/r2.out'"

R3="$WORK/bad-json"; make_claude_dir "$R3" 'x'
printf '{ this is not json' > "$R3/settings.json"
cp "$R3/settings.json" "$WORK/r3.before"
set +e; QM_CLAUDE_DIR="$R3" "$INSTALLER" --apply > "$WORK/r3.out" 2>&1; R3RC=$?; set -e
assert "settings.json 不是合法 JSON 時拒絕" "[[ ${R3RC} -ne 0 ]]"
assert "壞 JSON 不會被改寫" "cmp -s '$WORK/r3.before' '$R3/settings.json'"

R4="$WORK/no-settings"; rm -rf "$R4"; mkdir -p "$R4"
set +e; QM_CLAUDE_DIR="$R4" "$INSTALLER" --apply > "$WORK/r4.out" 2>&1; R4RC=$?; set -e
assert "settings.json 不存在時拒絕" "[[ ${R4RC} -ne 0 ]]"

# ── code review 補的：會弄壞使用者設定的幾種形狀 ─────────────────
echo "▸ 不會弄壞的形狀"

# 1) settings.json 是 symlink（dotfiles 管理：stow / chezmoi / yadm 都這樣）
SL="$WORK/symlink"; make_claude_dir "$SL" "$WORK/symlink/statusline.sh"
mkdir -p "$WORK/dotfiles"
mv "$SL/settings.json" "$WORK/dotfiles/settings.json"
ln -s "$WORK/dotfiles/settings.json" "$SL/settings.json"
cp "$WORK/dotfiles/settings.json" "$WORK/symlink.before"
set +e; QM_CLAUDE_DIR="$SL" "$INSTALLER" --apply > "$WORK/sl.out" 2>&1; SLRC=$?; set -e
assert "symlink 的 settings.json 安裝後仍然是 symlink" "[[ -L '$SL/settings.json' ]]"
assert "寫的是 symlink 指到的那個檔，不是把 symlink 換成普通檔" \
  "grep -q quotamonster-tee '$WORK/dotfiles/settings.json'"
set +e; QM_CLAUDE_DIR="$SL" "$INSTALLER" --uninstall --apply > /dev/null 2>&1; set -e
assert "symlink 情況下 --uninstall 還原成原本的 byte" \
  "cmp -s '$WORK/symlink.before' '$WORK/dotfiles/settings.json'"

# 2) CRLF 換行（Windows 編輯過、或 core.autocrlf 簽出來的 dotfiles）
CR="$WORK/crlf"; make_claude_dir "$CR" "$WORK/crlf/statusline.sh"
python3 - "$CR/settings.json" <<'PY'
import sys
p = sys.argv[1]
with open(p, "rb") as f:
    data = f.read()
with open(p, "wb") as f:
    f.write(data.replace(b"\n", b"\r\n"))
PY
cp "$CR/settings.json" "$WORK/crlf.before"
set +e; QM_CLAUDE_DIR="$CR" "$INSTALLER" --apply > /dev/null 2>&1; set -e
CRBAK="$(find "$CR" -name 'settings.json.bak-*' | head -1)"
assert "CRLF 檔的備份與原檔逐 byte 相同（不可以被偷偷轉成 LF）" \
  "cmp -s '$WORK/crlf.before' '$CRBAK'"
assert "CRLF 檔安裝後仍然是 CRLF" \
  "[[ \$(grep -c \$'\\r' '$CR/settings.json') -gt 0 ]]"
set +e; QM_CLAUDE_DIR="$CR" "$INSTALLER" --uninstall --apply > /dev/null 2>&1; set -e
assert "CRLF 檔 --uninstall 還原成原本的 byte" \
  "cmp -s '$WORK/crlf.before' '$CR/settings.json'"

# 3) 命令字串在檔案裡是 \u 跳脫的（json.dump 預設、很多格式化工具也這樣）
UE="$WORK/uescape"; rm -rf "$UE"; mkdir -p "$UE"
cat > "$UE/狀態列.sh" <<'INNER'
#!/usr/bin/env bash
cat >/dev/null
printf 'zh inner'
INNER
chmod +x "$UE/狀態列.sh"
python3 - "$UE" <<'PY'
import json, sys, os
d = sys.argv[1]
cfg = {"model": "opus[1m]",
       "statusLine": {"type": "command", "command": os.path.join(d, "狀態列.sh")},
       "theme": "dark"}
# ensure_ascii=True → 非 ASCII 會變成 \uXXXX
open(os.path.join(d, "settings.json"), "w").write(json.dumps(cfg, indent=2) + "\n")
PY
cp "$UE/settings.json" "$WORK/uescape.before"
set +e; QM_CLAUDE_DIR="$UE" "$INSTALLER" --apply > "$WORK/ue.out" 2>&1; UERC=$?; set -e
assert "\\u 跳脫的非 ASCII 路徑可以安裝" "[[ ${UERC} -eq 0 ]]"
set +e; QM_CLAUDE_DIR="$UE" "$INSTALLER" --uninstall --apply > /dev/null 2>&1; set -e
assert "\\u 跳脫的情況下 --uninstall 還原成原本的 byte" \
  "cmp -s '$WORK/uescape.before' '$UE/settings.json'"

# ── settings.json 的權限不可以被放寬 ─────────────────────────────
# os.replace() 換上去的是新建的檔，權限由當下 umask 決定、不繼承被換掉的那一個。
# 〔實測 2026-09-21〕一個 0600 的 settings.json（裡面放 hooks 與 env）
# 裝完之後變成 0644 —— 同群組與其他人都讀得到。
echo "▸ 權限"
PERM="$WORK/perm"
make_claude_dir "$PERM" "$PERM/statusline.sh"
chmod 0600 "$PERM/settings.json"
PERM_BEFORE="$(stat -f '%Lp' "$PERM/settings.json")"
QM_CLAUDE_DIR="$PERM" "$INSTALLER" --apply >/dev/null 2>&1
PERM_AFTER="$(stat -f '%Lp' "$PERM/settings.json")"
assert "0600 的 settings.json 裝完之後還是 0600（不是 0644）" \
  "[[ '${PERM_BEFORE}' == '${PERM_AFTER}' ]]"

# 同一件事在「已經裝過、再跑一次」那條路徑上也要成立
QM_CLAUDE_DIR="$PERM" "$INSTALLER" --apply >/dev/null 2>&1
assert "重複安裝也不放寬權限" \
  "[[ '${PERM_BEFORE}' == \"\$(stat -f '%Lp' '$PERM/settings.json')\" ]]"

# ── wrapper 必須用 rename 換，不可以就地覆寫 ──────────────────────
# wrapper 正在被每一次狀態列渲染呼叫。就地覆寫有一個 truncate 空窗，
# 〔實測〕落在那個空窗的渲染會讀到殘檔 —— 12 種長度的殘檔 stdout 全是 0 byte。
# rename 沒有那個空窗。兩者的可觀測差別：inode 會不會變。
echo "▸ wrapper 原子換檔"
INO_BEFORE="$(stat -f '%i' "$PERM/quotamonster-tee.sh")"
# 先弄髒它，確保接下來那次安裝真的有東西要換
printf '# dirty\n' >> "$PERM/quotamonster-tee.sh"
QM_CLAUDE_DIR="$PERM" "$INSTALLER" --apply >/dev/null 2>&1
INO_AFTER="$(stat -f '%i' "$PERM/quotamonster-tee.sh")"
assert "換 wrapper 走 rename（inode 改變），不是就地覆寫" \
  "[[ '${INO_BEFORE}' != '${INO_AFTER}' ]]"
assert "換完之後 wrapper 與 repo 裡的那份逐 byte 相同" \
  "cmp -s '$ROOT/scripts/quotamonster-tee.sh' '$PERM/quotamonster-tee.sh'"
assert "沒有留下 .qm-tmp 殘檔" \
  "[[ -z \$(find '$PERM' -name '*.qm-tmp' -print -quit) ]]"

# ── 之前沒測到的拒絕條件 ─────────────────────────────────────────
echo "▸ 之前沒測到的拒絕條件"

R5="$WORK/not-executable"; make_claude_dir "$R5" "$WORK/not-executable/statusline.sh"
chmod 644 "$R5/statusline.sh"
cp "$R5/settings.json" "$WORK/r5.before"
set +e; QM_CLAUDE_DIR="$R5" "$INSTALLER" --apply > "$WORK/r5.out" 2>&1; R5RC=$?; set -e
assert "命令指向不可執行的檔案時拒絕" "[[ ${R5RC} -ne 0 ]]"
assert "不可執行時不動 settings.json" "cmp -s '$WORK/r5.before' '$R5/settings.json'"

R6="$WORK/bad-type"; make_claude_dir "$R6" "$WORK/bad-type/statusline.sh"
python3 - "$R6/settings.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["statusLine"]["type"] = "static"
open(p, "w").write(json.dumps(d, indent=2) + "\n")
PY
cp "$R6/settings.json" "$WORK/r6.before"
set +e; QM_CLAUDE_DIR="$R6" "$INSTALLER" --apply > "$WORK/r6.out" 2>&1; R6RC=$?; set -e
assert "statusLine.type 不是 command 時拒絕" "[[ ${R6RC} -ne 0 ]]"
assert "type 不對時不動 settings.json" "cmp -s '$WORK/r6.before' '$R6/settings.json'"

# 同一個命令字串在檔案裡出現兩次（例如某個 hook 也跑同一支腳本）
R7="$WORK/ambiguous"; make_claude_dir "$R7" "$WORK/ambiguous/statusline.sh"
python3 - "$R7/settings.json" "$WORK/ambiguous/statusline.sh" <<'PY'
import json, sys
p, cmd = sys.argv[1], sys.argv[2]
d = json.load(open(p))
d["hooks"]["Stop"] = [{"hooks": [{"type": "command", "command": cmd}]}]
open(p, "w").write(json.dumps(d, indent=2) + "\n")
PY
cp "$R7/settings.json" "$WORK/r7.before"
set +e; QM_CLAUDE_DIR="$R7" "$INSTALLER" --apply > "$WORK/r7.out" 2>&1; R7RC=$?; set -e
assert "命令字串在檔案裡不只出現一次時拒絕（不猜該改哪一個）" "[[ ${R7RC} -ne 0 ]]"
assert "有歧義時不動 settings.json" "cmp -s '$WORK/r7.before' '$R7/settings.json'"

# --help 不可以把程式碼印出來當說明
set +e; HELP="$("$INSTALLER" --help 2>&1)"; set -e
assert "--help 不會把 set -euo pipefail 當成說明印出來" \
  "[[ '$HELP' != *'set -euo pipefail'* ]]"
assert "--help 印得出用法" "[[ '$HELP' == *'--uninstall'* ]]"

echo
REACHED_END=1
if (( FAIL == 0 )); then
  echo "✓ ${PASS} 項全數通過"
else
  echo "✗ ${FAIL} 項失敗（通過 ${PASS} 項）" >&2
  exit 1
fi
