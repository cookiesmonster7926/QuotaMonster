# Stage 0 結果 — 通知權限 spike

> 執行日期：2026-09-18 · 機器：MacBook Air M4 / macOS 27.0 (26A428) / arm64
> 原始 log：`docs/evidence/QMProbe-*.log`、`docs/evidence/QuotaMonsterProbe.log`

## 結論

| 問題 | 結果 |
|---|---|
| Q1 本機建置的 app 能不能取得通知授權 | ❌ **不能** |
| Q2 60pt 的 status item 會不會被推出螢幕 | ✅ **不會**（`window.origin.y = 923.0`） |
| Q3 bundle 有沒有被正確註冊成 app | ✅ 有（`directory: ~/Applications` / `/Applications`） |
| Q4 `minos` 陷阱有沒有擋掉 | ✅ 有（`minos 14.0`，`platforms: [.macOS(.v14)]` 生效） |

## Q1 的完整實驗矩陣

四個變體，每個都用**全新或已知狀態**的 bundle ID：

| 變體 | 安裝位置 | LSUIElement | bundle ID | NSApp.isActive | 授權前狀態 | 結果 |
|---|---|---|---|---|---|---|
| QuotaMonster | `~/Applications` | true | 首次 | — | notDetermined | **請求靜默掛住**，無對話框 |
| QuotaMonster | `/Applications` | true | 已被前次污染 | false | denied | `UNErrorDomain code=1` 立即失敗 |
| QMProbeB | `/Applications` | **false**（.regular） | 全新 | **true** | notDetermined | **請求靜默掛住**，無對話框 |
| QMProbeC | `/Applications` | true | 全新 | false | notDetermined | **請求靜默掛住**，無對話框 |

**每一次 `ncprefs` 的登錄數都是 0**，而同一台機器上有 79 個第三方 bundle 已登錄。
→ 這不是「使用者拒絕」，而是**系統從未把這個 app 登錄進通知中心**。

## 已排除的變因

- **安裝位置** — `~/Applications` 與 `/Applications` 行為相同。（這是上一輪唯一沒測到的變因，現在測掉了，假設不成立。）
- **LSUIElement / activation policy** — regular 與 accessory 行為相同。
- **app 是否 active** — B 組 `isActive = true` 仍然掛住。
- **殘留的 TCC 狀態** — 全新 bundle ID 仍然掛住；`tccutil reset` 回報查無紀錄。
- **簽章有效性** — `codesign -vvv --deep --strict` 回報 valid on disk、satisfies its Designated Requirement，簽章者為 Apple Development（Team PZ56996BR5），且**沒有 quarantine xattr**。

## 剩下唯一站得住的假設

**Gatekeeper / 公證。** `spctl -a -vvv -t exec` 對這個 bundle 回報 **rejected**——
Apple Development 憑證不是 Developer ID，且未經公證。
這台機器上每一個會發通知的第三方 app 都是 Developer ID + 公證過的。

無法進一步證實：本機終端機沒有讀取統一日誌的權限（`log show` 回傳 0 行），
所以拿不到 `usernoted` / `tccd` 的拒絕理由。

## 對 Stage 5 的影響

原生 `UNUserNotificationCenter` 這條路**在目前的簽章條件下不可用**。兩條出路：

**A. 取得 Developer ID 並公證**（需付費 Apple Developer 帳號，USD 99/年）
  → 原生通知、可操作按鈕、時間敏感通知、Focus 整合全部解鎖。
  → 也順便解決「把 app 給別台機器會被 Gatekeeper 擋」的問題。

**B. 不公證，改用備援**
  - `osascript -e 'display notification'` — **送達已實機確認（使用者看到橫幅）**。代價：歸屬於「指令碼編輯器」，圖示與名稱都不是我們的，且沒有動作按鈕。
  - app 自己的 `NSPanel` 浮出視窗 — 完全可控、不需要任何授權，但只在螢幕上、不進通知中心、不會在鎖定畫面出現。
  - `AVAudioPlayer` 音效 — 不需授權。
  - **選單列圖示本身的警示狀態** — 已經設計好（外圈依阻塞數等分），不需授權，而且是唯一「不打斷你但持續可見」的通道。

`NSUserNotification` 不是選項（macOS 11 起棄用）。

## 決定（2026-09-18）

使用者選擇 **B：不公證，走備援**。
Stage 5 改以「選單列警示狀態 + NSPanel 浮窗 + AVAudioPlayer 音效 + osascript 補歷史」實作。
Stage 1（資料層）完全不受影響。
