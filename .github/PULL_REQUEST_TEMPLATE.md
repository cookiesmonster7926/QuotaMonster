<!--
  這張表對應 CONTRIBUTING.md 的規矩。不適用的欄位寫「不適用」並說一句為什麼，
  不要整段刪掉 —— 刪掉之後審的人分不出「不適用」與「忘了做」。
-->

## 這個改動在回答什麼問題

<!-- 不是「改了什麼」，是「什麼問題現在沒有答案」。一到三句。 -->

## 你怎麼知道它成立

<!--
  跑了哪一支測試、哪一支診斷，看到什麼輸出。
  ⚠️ 每一句都標明它是哪一種：〔實測〕〔代理量測〕〔推論〕〔文件說〕。
  沒有親自跑過的一律標〔推論〕。
-->

## 它可能把什麼弄壞

<!-- 想不到就寫「想不到」—— 那也是一個可以被反駁的宣稱。 -->

---

## 檢查清單

**一定要跑的**

- [ ] `bash scripts/test.sh` 全綠（把最後一行貼在上面「你怎麼知道它成立」裡）
- [ ] 沒有用 `swift test` 代替 `scripts/test.sh`
- [ ] `rm -rf .build && swift build -c release` —— **乾淨**建置過一次
      （增量建置的 `Build complete` 是假象）
- [ ] 動到 `scripts/quotamonster-tee.sh` 或 `scripts/install_statusline_tee.sh` 的話，
      `bash scripts/test_statusline_tee.sh` 與 `bash scripts/test_install_statusline_tee.sh` 也跑過

**這個 repo 的死規矩**

- [ ] 新增的**判斷**放在 `QuotaMonsterCore`（App 層只有路由與繪圖 ——
      放進 App 層的判斷永遠不會有測試）
- [ ] 缺資料回 `nil`／畫「—」，沒有回 `0`、`0 秒` 或 `Date()`
- [ ] 需要分辨「看到它但不在那個狀態」與「整個沒看到它」的地方，做成了三態，
      不是一個 `nil` 撐兩種意思
- [ ] 新測試**我看過它是紅的**（說明你怎麼確認的）
- [ ] 註解與文件裡每個宣稱都標了〔實測〕／〔代理量測〕／〔推論〕／〔文件說〕，
      沒有把推論寫成量測，也沒有把品味寫成機制論
- [ ] 沒有新增第二份門檻／常數的字面量（要用就做成別名或引用）

**安全與隱私**

- [ ] 沒有 hardcode 個人資訊：email、憑證名稱與 Team ID、`/Users/<誰>` 這種絕對路徑、
      帳號 UUID
- [ ] 新增的 fixture 已去識別化（`scripts/capture_fixtures.py`）
- [ ] 沒有動 `Resources/Info.plist` 的 `CFBundleIdentifier`
      （通知授權綁在它上面）
- [ ] 把使用者控制的字串交給另一個直譯器（osascript / shell）的話：
      使用者字串前面有 `--`、標題那一格仍然是常數，
      而且測試**餵的是真的 payload**（只試引號逸出的測試在有漏洞的版本上也會過）
- [ ] 沒有新增任何網路呼叫（這個 app 的承諾之一是零網路；
      新增的話請在上面明講，並同步改 `.github/SECURITY.md`）
- [ ] 沒有新增會寫到 `~/.claude/` 底下的路徑
      （目前只有 statusline tee 的安裝腳本會，而且那是使用者自己跑的）
- [ ] 沒有用 `--no-verify` 之類的旗標繞過 git hook

**改到畫面的話**

- [ ] 附上 `--dark` 的渲染輸出（這個專案兩次因為看淺色渲染而得到相反的結論）
- [ ] 圖示的配色是看 **2x** 判的（Retina 的選單列是 2x）
- [ ] 沒有在 `GlyphRenderer` 或 `StatusItemController.dimmed` 裡引入任何仿射變換 API
- [ ] 離屏驗收的介面只用了 `Button` 與 `Text`
      （`Menu` / `Picker` / `Stepper` 在 `ImageRenderer` 底下會畫成紅色禁止符號，
      `ScrollView` 會畫成空的 —— 那是一張看起來很正常、但某個角落是假的圖）

**改到文件的話**

- [ ] `docs/` 的新條目寫成「**宣稱 + 證據 + 付過的代價**」
- [ ] 沒有拿 `docs/build-log.md` 當現況引用（它裡面有已知是錯的敘述）

---

## 相關 issue

<!-- Fixes #123 / 討論串連結。新功能請先開 issue 談過再送實作。 -->
