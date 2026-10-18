# 用 Slack 維護 QuotaMonster

> 給接手的人（或 Claude）：這份文件說明怎麼讓 Slack 成為這個專案的維護介面。
> 讀完你應該知道三件事：**資料放哪裡、Slack 看得到什麼、哪些事不能做。**

證據標記沿用本 repo 的約定：**〔實測〕** 親手跑過、**〔文件說〕** 引用別人的文件、
**〔推論〕** 我們自己推的、**〔未驗證〕** 還沒試過。

## 1. 現況盤點（2026-10-06）

〔實測〕以下都是當天對 GitHub 實際查詢的結果，不是看本地推測：

| 項目 | 結果 |
|---|---|
| 遠端 | `https://github.com/cookiesmonster7926/QuotaMonster`（public） |
| `main` | 本地與 `origin/main` 同為 `895f745`，沒有未推的 commit，工作區乾淨 |
| 遠端分支 | 只有 `main` |
| Tags | `v0.1.0`–`v0.4.0` 本地與遠端一致 |
| Releases | 4 個，最新 v0.4.0（含 DMG） |
| Issues / Milestones | **0 個 / 0 個** |
| GitHub Projects | 未能查（token 沒有 `read:project`）；〔推論〕沒有，因為沒有人建過 |
| 沒進 git 的東西 | 只有 `.build/`、`dist/`、`.DS_Store`（都是 `.gitignore` 刻意排除） |

**重點：程式碼與文件全在 GitHub 上了，但「進度與任務」目前不在 GitHub 上。**
它們活在 `docs/quotamonster.md` 第五節（散文）與本機的 Claude 記憶裡。
Slack 只能看到 GitHub 上有的東西，所以**第 3 節要先做，Slack 才有東西可看。**

## 2. 架構：誰是資料來源，誰只是窗口

```
GitHub Issues + Milestones + Project(Roadmap)   ← 唯一的真相來源
        │ 事件（開 issue、關 issue、PR、release、CI）
        ▼
Slack #quotamonster（GitHub app 訂閱）          ← 通知與討論，不存狀態
```

規則：**狀態只存在 GitHub。** Slack 訊息會被洗掉，不能當紀錄。
在 Slack 決定的事，要回寫成 issue 或 comment，否則等於沒決定。

## 3. 先把任務放進 GitHub（Slack 的前置條件）

### 3.1 甘特圖

GitHub Projects 的 **Roadmap 版面**就是甘特圖（依 issue 的開始／結束日期畫橫條）。
〔文件說〕Slack 的 GitHub app 不會把它畫進頻道；Slack 看得到的是**事件**
（誰開了、誰關了、哪個 milestone 動了），甘特圖本身要點連結回 GitHub 看。
〔推論〕所以做法是把 Roadmap 的網址釘在頻道頂端，Slack 負責「有變動就通知」。

建立步驟（需要使用者本人執行，因為要擴權 token）：

```bash
gh auth refresh -s project                       # 給 token 加 project 權限
gh project create --owner cookiesmonster7926 --title "QuotaMonster Roadmap"
# 之後在網頁上把 View 切成 Roadmap，並新增 Start date / Target date 兩個欄位
```

### 3.2 Milestones 與 Labels

Milestone 用來表示「版本」，一個 milestone 對應一個要出的 tag（例如 `v0.5.0`）。
建議的 label：`type:feature`、`type:bug`、`type:measure`（量測中，結論未定）、
`blocked`（等條件）。

### 3.3 初始任務（從 `docs/quotamonster.md` 第五節摘出，**尚未建立**）

下面是我讀第五節整理的候選清單，**還沒有開成 issue** —— 要使用者確認後才建，
因為這個 repo 是 public，開出去所有人都看得到。

| 候選 issue | 類型 | 狀態 |
|---|---|---|
| 修 `ranFor`：`TranscriptCursor` 往前掃時順手記下最後一則真人訊息 | feature | 可動工；它擋著下一項 |
| 完成訊號要不要出聲 | measure | `blocked`：要先修 `ranFor` 再重問（第三節第 33 條） |
| workflow 的 `journal.jsonl` 每拍整份重讀 | feature | 可動工；剩下 62.8 ms 的主要來源 |
| FSEvents 監看取代 3 秒輪詢 | feature | 可動工 |
| 卡住／閒置 agent 偵測 | feature | 資料層夠了，缺門檻與 UI |
| 偏好視窗沒有真機開窗的紀錄 | measure | 只驗過離屏渲染 |
| `heartbeat + bootMarker`（Stage 7 步驟 10） | feature | `blocked`：等使用者點頭 |

⚠️ 第二節的「寫下來的拒絕」（Sparkle 自動更新、T2 對一般 Agent 扇出等）
**不是待辦，不可以開成 issue。** 加回來之前先讀理由。

## 4. 把 Slack 接上 GitHub

〔未驗證〕以下指令來自 Slack 的 GitHub app 公開用法，這個 repo 還沒實際接過，
第一次做完請回來把標記改成〔實測〕或更正。

1. 在 Slack 工作區安裝 GitHub app，並在頻道裡 `/github signin`。
2. 訂閱：
   ```
   /github subscribe cookiesmonster7926/QuotaMonster issues pulls releases workflows
   ```
   `workflows` 會推 CI 結果（`.github/workflows/ci.yml`）。
   **不建議訂 `commits`**：這個 repo 的 commit 訊息很長，會洗版。
3. 檢查：`/github subscribe list`。
4. 把第 3.1 節的 Roadmap 網址、`docs/quotamonster.md` 連結釘在頻道。

## 5. 在 Slack 維護時的日常流程

| 想做的事 | 做法 |
|---|---|
| 看進度 | 開釘選的 Roadmap；或 `/github` 指令看 issue 列表 |
| 新增任務 | 開 GitHub issue，指定 milestone 與日期；Slack 會收到通知 |
| 任務完成 | PR 的描述寫 `Fixes #N`，merge 後 issue 自動關、Slack 自動通知 |
| 出版本 | 依 `CONTRIBUTING.md` 打 tag、建 release；Slack 會收到 release 通知 |

驗收指令不變（見根目錄 `CLAUDE.md`）：`bash scripts/test.sh`、
`rm -rf .build && swift build -c release`。**Slack 上任何人說「測過了」都不算，
要有指令輸出。**

## 6. 不可以做的事

1. **不可以 `git push --all` 或 `git push --mirror`。** 本機另有一個不可公開的分支，
   這兩個指令會把它一起推上 public repo。一律明確寫 `git push origin main`
   與 `git push origin <tag>`。
2. **不可以把任何 token / webhook URL 貼進 Slack 或 commit。**
   Slack 的 incoming webhook URL 等同密碼；若需要，放環境變數，不進 repo
   （跨專案規則：禁止 hardcode secrets）。
3. **不可以在 Slack 裡貼 Claude Code 的 transcript 或 `~/Library/Application Support/QuotaMonster/`
   下的檔案**，裡面有個人的使用紀錄。
4. 這個 app 本身的網路行為（只有 `ReleaseChecker.swift` 可以連網）**與 Slack 整合無關**，
   不要為了「讓 app 回報進度到 Slack」去動它。Slack 整合只發生在 GitHub 那一側。

## 7. 待確認

- [ ] 使用者執行 `gh auth refresh -s project` 並建立 Project
- [ ] 使用者確認第 3.3 節的清單，才開 issue
- [ ] 第一次接 Slack 後，把第 4 節的〔未驗證〕改成〔實測〕
