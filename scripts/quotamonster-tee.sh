#!/usr/bin/env bash
# 為什麼需要這支腳本：
# ~/.claude.json 的 cachedUsageUtilization 不是每回合刷新。實測它可以整整 16 小時
# 沒更新，而且裡面那筆 five_hour 的 resets_at 早就過去了 —— 它描述的是一個已經不存在
# 的窗口。要拿到活的額度數字，唯一的途徑是旁聽 Claude Code 餵給 statusLine 的 payload。
# 那份 payload 同時是唯一能拿到 context_window.used_percentage 的地方。
#
# 這支腳本夾在 Claude Code 與使用者原本的狀態列腳本之間：把 stdin 收下來寫進快取，
# 然後一個 byte 不差地交棒給原本的腳本。
#
# 環境變數（安裝腳本會把 INNER 寫成安裝當下的真實值）：
#   QM_STATUSLINE_INNER      內層腳本路徑。**空的或沒設 = 沒有內層**，
#                            這時 wrapper 自己印一行最小狀態列（見第 3 段）。
#   QM_STATUSLINE_CACHE_DIR  快取目錄
#   QM_STATUSLINE_TRACE      （選用）shadow 量測的 log 檔路徑。測試用的明確覆寫。
#
# ══ 這支腳本的唯一承諾 ══
# 使用者的狀態列一個 byte 都不變，而且**永遠不會因為快取出問題而消失**。
# 官方文件：離開碼非 0、或輸出為空，狀態列會整條變成空白。
#
# 所以結構是「先把 payload 收進記憶體，再盡力寫快取，最後一定把完整的 payload
# 交給內層」。快取的每一步都可以失敗，失敗全部吞掉，內層拿到的東西不受影響。
#
# ⚠️ 這支腳本刻意「沒有」set -euo pipefail。
#    set -e 會讓任何一個無關緊要的失敗（例如快取目錄不可寫）直接終止腳本，
#    在內層跑起來之前就把狀態列弄不見。
#
# ⚠️ 先讀進變數、不是先寫檔。
#    早期版本是 `cat > "$tmp"` 然後把那個檔餵給內層。code review 抓到：
#    快取目錄只要不可寫（磁碟滿、權限跑掉），整條狀態列就以 rc=1、零輸出消失。
#    實測重現過。現在磁碟壞掉最多只是快取沒更新。
#    代價：bash 變數放不下 NUL。〔推論，非實測〕statusLine payload 來自
#    JSON.stringify，裸 NUL 會被跳脫成 \u0000（六個 ASCII 字元），所以不該出現。
#    ⚠️ **但這個推論猜錯一次的代價是不對稱的。**〔實測 2026-09-21〕餵一份含裸 NUL
#    的 72 byte payload：`read` 在 NUL 處停住，內層只收到 59 byte，而那份截斷版
#    **經 rename 蓋掉了上一筆完整的快取**（`[ -s ]` 只檢查非空，不檢查完整）。
#    所以現在不靠那個推論：`read -r -d ''` 讀到 NUL 回 0、讀到 EOF 回非 0，
#    據此就知道有沒有被截斷。
#
#    ⚠️ 附帶一提：這一段原本自己就含著**一個真的 NUL byte** —— 作者想寫 \u0000，
#    寫進去的是 \0 本人。已清掉。
#
# ⚠️ /bin/bash 在 macOS 是 3.2.57。read -N 是 4.1 才有的，不可使用。
#    這裡用到的 read -r -d ''、[[ =~ ]] + BASH_REMATCH、{36} 量詞在 3.2 都可用。

# ⚠️ **刻意沒有預設值。** 這裡原本是 `${QM_STATUSLINE_INNER:-$HOME/.claude/statusline.sh}`，
# 而那個猜測有兩個問題：(一) 猜錯時（那個檔不存在）狀態列整條變空白，
# 而且錯誤不會出現在任何地方；(二) 它讓測試在**開發者剛好有那個檔**的機器上
# 為了錯的理由通過 —— 實測 2026-09-21 的「內建那一行帶得出模型」就是這樣過的。
# 空的代表「沒有內層」，那是一條合法的路，不是錯誤。
INNER="${QM_STATUSLINE_INNER-}"
DIR="${QM_STATUSLINE_CACHE_DIR:-$HOME/Library/Application Support/QuotaMonster/statusline}"

# INNER 指到自己會變成 fork bomb。-ef 是 bash 內建的 inode 比對，不 fork。
if [ "$INNER" -ef "$0" ] 2>/dev/null; then
  cat >/dev/null 2>&1
  printf 'QuotaMonster tee: QM_STATUSLINE_INNER points at the wrapper itself'
  exit 0
fi

# ── 1. 先把 payload 完整收下來 ────────────────────────────────────
# -d '' 讀到 NUL 或 EOF 為止，所以換行與結尾的換行都原樣保留。
#
# ⚠️ 離開碼是載重的，不是可以省略的細節：
#     rc≠0 → 讀到 **EOF**，也就是 stdin 全部進來了（正常情況）
#     rc=0  → 讀到一個 **NUL 分隔符**，代表後面還有 byte 沒讀到 → payload 被截斷
IFS= read -r -d '' payload
if [ $? -eq 0 ]; then payload_truncated=1; else payload_truncated=0; fi

# ── 2. 盡力寫快取 ────────────────────────────────────────────────
tmp=""
cleanup() { [ -n "$tmp" ] && rm -f "$tmp" 2>/dev/null; return 0; }
# 訊號處理要真的收工（只做 rm 不 exit 會讓行程回頭繼續等 stdin）。
# ⚠️〔實測 2026-09-21〕**這三個 trap 現在守的窗口很窄**：它們裝在第 1 段那個
# 阻塞的 `read` **之後**，所以 read 期間收到 TERM 靠的是預設處置，不是它們。
# 把三行全刪掉，scripts/test_statusline_tee.sh 那則 SIGTERM 測試照樣通過。
# 它們真正還有用的地方只剩「read 完成之後、交棒之前」那幾毫秒的 .tmp.$$ 清理。
# 留著是因為那個清理仍然是對的，不是因為那則測試守得住它。
trap 'cleanup; exit 143' TERM
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 129' HUP
trap cleanup EXIT

# 截斷的 payload 絕不可以蓋掉上一筆完整的快取 —— 一個舊但完整的讀數
# 遠勝過一個新但殘缺的。剩下的 byte 在 bash 裡本來就存不住（含 NUL），
# 所以這裡能做的唯一正確的事就是「不要動快取」。
if [ -n "$payload" ] && [ "$payload_truncated" -eq 0 ]; then
  # umask 要在 mkdir **之前**設，否則第一次渲染時若呼叫端的 umask 很嚴，
  # 會建出一個永久不可寫的快取目錄（code review 抓到，實測 umask 0222 → 0555）。
  old_umask=$(umask)
  umask 077

  if [ -d "$DIR" ] || mkdir -p "$DIR" 2>/dev/null; then
    tmp="$DIR/.tmp.$$"
    if printf '%s' "$payload" > "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
      # 純 bash 取 session_id，字元集鎖死成 36 個十六進位/連字號，
      # 所以惡意的 "session_id": "../../../etc/passwd" 不可能變成檔名。
      #
      # 在 LC_ALL=C 的子 shell 裡比對：payload 裡只要有一個非 UTF-8 的 byte
      # （來自 exFAT/SMB 掛載點的路徑就會），UTF-8 語系下的 [[ =~ ]] 會整個比對失敗。
      # 用子 shell 是為了不讓 LC_ALL 汙染到內層腳本 —— 它的 ${#input} 要照使用者的語系算。
      sid=$(LC_ALL=C
            if [[ $payload =~ \"session_id\"[[:space:]]*:[[:space:]]*\"([0-9a-fA-F-]{36})\" ]]
            then printf '%s' "${BASH_REMATCH[1]}"; fi)
      # 認不出 session_id 也要留下來：萬一未來版本把這個鍵改名，
      # 帳號層級的額度資料仍然進得來（那份資料本來就與 session 無關）。
      [ -n "$sid" ] || sid="_unkeyed"

      # rename(2) 是原子的。Claude Code 會在新事件觸發時 abort 執行中的腳本，
      # 直接寫檔會讓讀取端看到寫一半的 JSON。
      mv -f "$tmp" "$DIR/$sid.json" 2>/dev/null || rm -f "$tmp" 2>/dev/null
    else
      # 建得出檔案但寫不進去（磁碟滿），或寫出來是空的 —— 不要拿它蓋掉上一筆好的。
      rm -f "$tmp" 2>/dev/null
    fi
    tmp=""
  fi

  umask "$old_umask"
fi

# ── 2b. 選用的 shadow 量測 ───────────────────────────────────────
# 要回答的問題：**一個回合的第一次狀態列渲染，會不會早於該回合第一個 API 回應？**
#
# 為什麼還沒有答案：〔實測，讀 Claude Code 2.1.277 的二進位〕payload 的
# rate_limits 是從行程記憶體的 `Eu.rawUtilization` 重發的，只有 API 回應才更新。
# 所以「閒置很久之後的第一次渲染會帶出舊數字」在結構上成立 —— 但「第一次渲染
# 早於第一個回應」這一步我沒有量到，它到今天為止仍然是**推論**。
#
# 快取檔只留最新一份，所以歷史在那裡看不到。這支 log 補的就是那段歷史：
# 每一次渲染都記一行，於是「渲染了但數字沒變」與「數字變了」在時間軸上分得開。
#
# ⚠️ **這支 log 會輪替，上限 1MB。** 它每次渲染寫一行（實測約 150KB／天），
# 沒有上限就是在使用者磁碟上無限成長 —— 而 `usage-history.jsonl` 與
# `watch-log.jsonl` 都有 30 天保留，只有它漏掉了（code review 2026-09-22）。
#
# ⚠️ 清理由 **wrapper 自己做**，不交給 app：這個檔案是 bash 在 append，
# 而 app 的 prune 走 tmp + rename 換檔 —— 那會把正在寫的那一行丟掉，
# 而且兩個寫入者搶同一個檔。
#
# 格式（一行一次渲染，tab 分隔）：
#   <epoch 秒>\t<"rate_limits": 之後到結尾的原文>
# ⚠️ 第二欄**不是**單獨合法的 JSON —— 它含著 payload 自己的收尾大括號
#    （實測：…"resets_at":1790402400}}} 最後是三個）。解析時把尾端多的括號去掉。
#    刻意不做更精細的抽取：在 bash 3.2 裡平衡括號要付的代價遠高於這個瑕疵。
#
# ### 怎麼開關：用一個**開關檔**，不動 settings.json
#     開：touch "$DIR/../trace-usage.on"
#     關：rm     "$DIR/../trace-usage.on"
#     看：       "$DIR/../trace-usage.log"
# 刻意不走環境變數：那會逼使用者改 statusLine.command，而這整套工具的承諾
# 就是「settings.json 只動那一個字串」。開關檔讓量測的開與關都不碰設定。
# （QM_STATUSLINE_TRACE 仍然可以明確覆寫路徑，測試用的就是它。）
#
# ⚠️ 預設**完全不做** —— 開關檔不存在就一個 byte 都不寫，連 stat 都只有一次。
# ⚠️ 只記完整的 payload。截斷的那一種本來就不可信，記進去只會汙染量測。
# ⚠️ 失敗一律吞掉，理由與快取相同：量測不可以把狀態列弄不見。
trace_to="${QM_STATUSLINE_TRACE:-}"
if [ -z "$trace_to" ] && [ -f "$DIR/../trace-usage.on" ]; then
  trace_to="$DIR/../trace-usage.log"
fi
if [ -n "$payload" ] && [ "$payload_truncated" -eq 0 ] && [ -n "$trace_to" ]; then
  rl=$(LC_ALL=C
       if [[ $payload =~ \"rate_limits\":(.*)$ ]]; then printf '%s' "${BASH_REMATCH[1]}"; fi)
  [ -n "$rl" ] || rl="(沒有 rate_limits)"
  # 寫之前看一眼大小。超過就只留後半 —— 要的是「最近的歷史」，不是全部。
  # `stat` 每次渲染一次，成本可以忽略；真正的砍檔很少發生。
  trace_max=1048576
  trace_size=$(stat -f%z "$trace_to" 2>/dev/null || echo 0)
  if [ "$trace_size" -gt "$trace_max" ] 2>/dev/null; then
    if tail -c $((trace_max / 2)) "$trace_to" > "$trace_to.tmp" 2>/dev/null; then
      mv -f "$trace_to.tmp" "$trace_to" 2>/dev/null || rm -f "$trace_to.tmp" 2>/dev/null
    else
      rm -f "$trace_to.tmp" 2>/dev/null
    fi
  fi
  printf '%s\t%s\n' "$(date +%s)" "$rl" >> "$trace_to" 2>/dev/null || true
fi

# ── 3. 交棒 ──────────────────────────────────────────────────────
# ⚠️ 內層不可執行時**不可以**靜靜地收工。〔實測〕INNER 指到不存在的檔 → rc=127、
# stdout 0 byte；INNER 是 0644 → rc=126、stdout 0 byte。兩種都讓狀態列整條變空白，
# 而且錯誤不會出現在任何地方 —— 使用者只看到狀態列不見了，查不到原因。
# 這與這支腳本檔頭寫的唯一承諾直接衝突，所以改成把原因印在狀態列上。
#
# 這條路徑尤其容易被踩到：INNER 的預設值是 $HOME/.claude/statusline.sh，
# 於是「環境變數沒被傳進來」從一個會報錯的情況變成一條靜默路徑。
# ── 沒有內層：自己印一行 ─────────────────────────────────────────
#
# 為什麼要有這條路：〔實測 2026-09-21〕`~/.claude.json` 的 `cachedUsageUtilization`
# 已經**不再更新**（檔案一直被重寫，但 fetchedAtMs 凍了 3.9 天），所以
# **沒有 tee 就沒有額度數字**。而 tee 原本要求使用者已經有自訂 statusLine ——
# 沒有的人（多數新使用者）連裝都裝不了。現在「沒有內層」是合法狀態。
#
# ⚠️ 用純 bash 抽欄位，不叫 python3：這條路每次渲染都會跑，
# python3 的啟動成本（~30ms）遠高於整個 wrapper 現在的 6.5ms。
# ⚠️ 欄位缺席就整段不出現 —— 絕不印出孤兒的「%」或空欄位。
if [ -z "$INNER" ]; then
  parts=""
  add() { [ -z "$1" ] || { [ -z "$parts" ] && parts="$1" || parts="$parts · $1"; }; }

  m=$(LC_ALL=C
      if [[ $payload =~ \"display_name\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]
      then printf '%s' "${BASH_REMATCH[1]}"; fi)
  add "$m"

  # context_window 底下有巢狀的 current_usage（也帶 }），所以不能用 [^}]*。
  # 改成先把 payload 切成「context_window 之後、rate_limits 之前」那一段。
  # ⚠️ 這依賴 context_window 排在 rate_limits 前面〔實測 2.1.277 是這樣〕。
  # 順序若改變，這一格會消失而不是印出錯的數字 —— 那是可以接受的退化方向。
  if [ "${payload#*\"context_window\"}" != "$payload" ]; then
    seg="${payload#*\"context_window\"}"
    seg="${seg%%\"rate_limits\"*}"
    c=$(LC_ALL=C
        if [[ $seg =~ \"used_percentage\"[[:space:]]*:[[:space:]]*([0-9]+) ]]
        then printf '%s' "${BASH_REMATCH[1]}"; fi)
    [ -z "$c" ] || add "ctx ${c}%"
  fi

  # 這兩個可以用 [^}]* —— five_hour / seven_day 底下沒有巢狀物件。
  h=$(LC_ALL=C
      if [[ $payload =~ \"five_hour\"[^}]*\"used_percentage\"[[:space:]]*:[[:space:]]*([0-9]+) ]]
      then printf '%s' "${BASH_REMATCH[1]}"; fi)
  [ -z "$h" ] || add "5h ${h}%"
  d=$(LC_ALL=C
      if [[ $payload =~ \"seven_day\"[^}]*\"used_percentage\"[[:space:]]*:[[:space:]]*([0-9]+) ]]
      then printf '%s' "${BASH_REMATCH[1]}"; fi)
  [ -z "$d" ] || add "7d ${d}%"

  # ⚠️ 一個 byte 都不印會讓狀態列整條消失，所以最後一定要有東西。
  [ -n "$parts" ] || parts="QuotaMonster"
  trap - TERM INT HUP EXIT
  printf '%s' "$parts"
  exit 0
fi

# ⚠️ 內層**設了但不可執行**與「沒有內層」是兩件事：前者代表設定壞了，要講出來。
# 〔實測〕INNER 指到不存在的檔 → rc=127、stdout 0 byte；INNER 是 0644 → rc=126、
# stdout 0 byte。兩種都讓狀態列整條變空白，而且錯誤不會出現在任何地方。
if [ ! -x "$INNER" ]; then
  printf 'QuotaMonster tee: 內層狀態列腳本不可執行（%s）' "$INNER"
  exit 0
fi

# 先把 trap 拆掉：這之後收到訊號的行為要跟「沒有 wrapper」完全一樣。
trap - TERM INT HUP EXIT
printf '%s' "$payload" | "$INNER"
exit "${PIPESTATUS[1]}"
