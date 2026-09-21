# 參與這個專案

先說一句最重要的：**這個 repo 的規矩不太一樣，而且那些不一樣是有代價換來的。**
下面每一條都能在 `docs/quotamonster.md` 找到對應的證據與「這個 repo 為它付過什麼」。
不照著做的 PR 不會因為「風格不合」被退，會因為**它會把已經修好的 bug 放回來**被退。

## 動手前先讀

1. **`docs/quotamonster.md`** —— 32 條不可違反的規矩、16 條寫下來的拒絕、
   27 處「曾經這樣想、後來被資料推翻」。從你要改的那一節讀起就好，不必整本。
2. **`CLAUDE.md`** —— 上面那本的一頁版。
3. ⚠️ **`docs/build-log.md` 不是現況。** 那是施工紀錄，裡面**有已知是錯的敘述**
   （哪幾條錯了，列在 `docs/quotamonster.md` 第三節）。它只能當歷史看，
   不可以拿來當「現在是這樣做的」的根據。

## 環境與驗收指令

需要：macOS 14 以上、Swift 6 工具鏈（Xcode 或 Command Line Tools 都可以）。
**不需要 Xcode**，這個專案不用 `xcodebuild`，也不為了跑測試去動全域的 `xcode-select`。

```bash
bash scripts/test.sh                         # Swift 測試
bash scripts/test_statusline_tee.sh          # wrapper 的對照測試（shell）
bash scripts/test_install_statusline_tee.sh  # 安裝腳本的保證（shell）
rm -rf .build && swift build -c release      # 乾淨的 release 建置
bash scripts/make_app.sh                     # 組 .app 並裝到 ~/Applications
```

〔實測 2026-09-21，macOS 27.0 / arm64〕上面前三項的結果：
Swift 55 套件 521 則測試全過、tee 67 項全過、安裝腳本 51 項全過。

### ⚠️ 不可以直接 `swift test`

`scripts/test.sh` 做的事是補上兩條 framework 搜尋路徑與 rpath ——
`xcode-select` 指向 CommandLineTools 時，SwiftPM 不會自己補上 swift-testing
需要的那兩條。沒有它，測試不是失敗，是**連載入都失敗**，
而那很容易被讀成「這台機器跑不了測試」。要加參數就直接接在後面：
`bash scripts/test.sh --filter Glyph`。

### ⚠️ 增量建置的 `Build complete` 是假象

有些東西（特別是 `GlyphRenderer` 那條「不可以出現仿射變換 API」的規矩）
只有在乾淨建置時才會真的被重新編譯。驗收一律：

```bash
rm -rf .build && swift build -c release
```

另外：`Package.swift` 裡的 `platforms: [.macOS(.v14)]` **不可刪**。
〔實測 2026-09-21〕這台機器上 `swift --version` 印出的預設 target 是
`arm64-apple-macosx28.0` —— 高於執行中的系統。少了那一行，
包成 .app 之後 LaunchServices 會以 `-10825` 拒絕啟動，
但當成純 CLI binary 跑又完全正常，**會騙過天真的 smoke test**。

---

## 這個 repo 的七條不尋常規矩

### 1. 決策只能放 `QuotaMonsterCore`

`Sources/QuotaMonsterCore/` 是純邏輯：沒有 AppKit、沒有 `Date()`、沒有計時器。
`Sources/QuotaMonsterApp/` **只有路由與繪圖**。

為什麼是死規矩：`Package.swift` 的 testTarget 只涵蓋得到 Core 的東西，
放進 App 層的判斷**就永遠不會有測試**。所以「該不該發這則通知」「這個 workflow
算完成還是算不明」「這行字要寫什麼」全部在 Core，App 只負責把結果畫出來。

實務上的判準：你寫的東西裡有 `if`，而那個 `if` 在回答一個關於世界的問題，
它就該在 Core。

### 2. `nil` 是「不知道」，不是零 —— 而且要分兩層

- 缺資料一律回 `nil`、畫「—」。**絕對不要**回 `0%`、`0 秒` 或 `Date()`。
  `0` 是一個關於世界的斷言（「它跑了 0 秒」），而你其實不知道。
- 更細一層：**「看到它、但它不在那個狀態」與「整個沒看到它」是兩件事。**
  前者是正面證據，可以當場動手；後者不是證據，要給寬限期或直接切斷。
  一個 `nil` 同時代表這兩件事，就會在兩個方向各錯一種。

這是這個 repo 犯過最多次的錯（至少三次，各付過各的代價）。
需要三態就做成三態的列舉，不要用 optional 硬撐
（範例：`TurnReadout` 的 `finished` / `unfinished` / `inconclusive`）。

### 3. 「實測」「代理量測」「推論」「文件說」是四件不同的事

註解與文件裡**不可以混用**。你寫的每一個宣稱都要讓下一個人看得出它是哪一種：

```swift
/// 〔實測 2026-09-21〕餵一份含裸 NUL 的 72 byte payload，內層只收到 59 byte。
/// 〔推論，沒有量過〕重疊的機率很低。
```

為什麼這條要寫進貢獻指南：這個 repo 裡每一條 ⚠️ 都被下一個人**當成實測結果在信**。
一句沒標的推論混進去，會慢慢侵蝕掉整份註解的可信度 —— 而那正是它唯一的價值。
**沒有親自跑過的，一律標「推論」。** 不確定要標哪一種，就把你實際做過的動作寫出來
（「讀碼確認」「grep 全庫」「讀 binary」）。

順帶一提：把品味寫成機制論也是一種說謊。
「這樣比較好看」就寫「這樣比較好看」，不要編一個效能理由。

### 4. 測試要先看它紅

新測試寫完，**先確認它在沒有修正的版本上會失敗**，再去寫實作。
這個 repo 有過一則說謊的測試（`#expect(A == 300)` 用來釘住「A 是 B 的別名」——
把 A 改成另一個字面量 `300` 它照樣會過）。
一則永遠綠的測試比沒有測試更糟：它會讓下一個人以為那條規矩有人在守。

修 bug 的 PR 請附上「這則測試在修正之前是紅的」這句話，以及你怎麼確認的。

安全性相關的測試要**餵真的 payload**：只試引號逸出的測試，在有 RCE 的版本上也會過。
範本在 `Tests/QuotaMonsterCoreTests/OSAScriptCommandTests.swift` ——
它真的跑一次 `osascript`、斷言 sentinel 檔案沒被建出來，
旁邊還放了一則**控制組**（同一個 payload 拿掉 `--` 就真的會執行），
用途不是抓 bug，是證明前一則有牙齒。

### 5. 門檻與常數只能定義在一處

第二份字面量一律做成別名或引用。兩份字面量會在某一次只改了一邊之後，
讓兩個地方對同一件事的定義差一截，而且不會有人馬上發現。

### 6. 把使用者控制的字串交給另一個直譯器時，威脅模型不只是引號逸出

`osascript` / shell / SQL 都算。它們**自己的參數解析**就是攻擊面：
`-eproperty p:(do shell script "…")` 會被 `osascript` 的 getopt 吃掉當成另一段
`-e`，而 property 的初始值在載入時就求值 —— 跑在 `run` handler 之前。
所以使用者字串前面一定要有 `--`，而且標題那一格永遠是常數。

改到 `Sources/QuotaMonsterCore/Notify/OSAScriptCommand.swift` 的 PR，
請把那整段註解讀完再動 —— 它寫明了 `--` 守的是**哪一格**，
以及為什麼另外兩格是被別的機制（而且是**偶然**）擋住的。

### 7. 診斷指令不可以說謊

`--dump`、`--render`、`--trace-*` 這些是這個專案唯一的觀測手段。

- 註解說它畫了什麼，就必須真的畫 —— 用 `exit(1)` 的自我斷言釘住，不是用註解。
- 配色**一律用 `--dark` 檢查**（使用者的選單列與面板是深色的；
  這個專案已經兩次因為看淺色渲染而得到相反的結論）。
- **判配色要看 2x** —— Retina 的選單列把 22pt 畫成 44 個裝置像素。
- 合成資料要在輸出裡講明它是合成的。
- trace 類的輸出直接寫 fd 1，不要用 `print`：stdout 不是 TTY 時 `print` 是
  4KB 區塊緩衝，導到檔案再 tail 會看到空檔案，然後以為工具沒在跑。
- ⚠️ AppKit 包裝的 SwiftUI 控制項（`Menu` / `Picker` / `Stepper`）在 `ImageRenderer`
  底下會畫成一個紅色禁止符號，`ScrollView` 會畫成空的。
  要離屏驗收的介面只能用 `Button` 與 `Text`。

完整的「哪一支回答哪一個問題、哪一支**不能**回答什麼」在
`docs/quotamonster.md` 第四節。

---

## 提 PR 之前

- **先開 issue 談。** 特別是新功能 —— `docs/quotamonster.md` 第二節有 16 條
  **寫下來的拒絕**（例如：不自建安靜時段排程器、完成訊號不出聲、
  `killed` 的 run 完全不發通知）。那些不是待辦，是決定。
  要推翻其中一條沒問題，但請帶著推翻它的理由來，不要直接送實作。
- **一個 PR 一件事。** 順手的重構請分開送。
- **commit 訊息**沿用現有風格：`type(scope): 說明`，說明用中文，
  寫「為什麼」而不是「改了哪幾行」。例如
  `fix(usage): 檔案很新不等於數字很新 —— 三處讓資料說謊的地方`。
- **不要用 `--no-verify` 之類的旗標繞過 git hook。**
- **不可以 hardcode 個人資訊**（email、憑證名稱與 Team ID、`/Users/<你>` 這種
  絕對路徑、帳號 UUID）。要用自己的簽章身分就走環境變數
  （`CODESIGN_IDENTITY=… bash scripts/make_app.sh`），不要寫進檔案。
  fixture 一律去識別化 —— `scripts/capture_fixtures.py` 有現成流程，
  而且它看到 `sk-ant-` 開頭的內容會直接以非零碼結束。
  這條規矩是為一次**已經發生的**外洩補的。
- **不要動 `Resources/Info.plist` 的 `CFBundleIdentifier`** ——
  通知授權綁在它上面，改了等於變成另一個 app，使用者做過的授權決定會歸零。
- 動到 `docs/` 的話：這個 repo 的文件格式是「**宣稱 + 證據 + 付過的代價**」。
  代價那一欄不是裝飾，它是下一個人判斷「這條可不可以繞過」的唯一依據。

### PR 描述請回答三件事

1. **這個改動在回答什麼問題？**（不是「改了什麼」）
2. **你怎麼知道它成立？** —— 跑了哪一支測試、哪一支診斷、看到什麼輸出。
   標明那是實測還是推論。
3. **它可能把什麼弄壞？**

`.github/PULL_REQUEST_TEMPLATE.md` 有對應的檢查清單。

---

## 回報問題

- 一般 bug 與功能建議：開 issue，用 `.github/ISSUE_TEMPLATE/` 裡的表單。
- **安全性問題請不要開公開 issue** —— 走 GitHub 的 Private vulnerability reporting，
  細節見 [`.github/SECURITY.md`](.github/SECURITY.md)。
- ⚠️ 貼 `--dump` 輸出之前先看一眼：裡面有你的家目錄路徑、專案名、session 名稱，
  以及 subagent 的任務描述。該遮的先遮掉。

## 授權

本專案採用 **Apache License 2.0**。送出 PR 即表示你同意你的貢獻以同一份授權釋出。
