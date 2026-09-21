# 變更紀錄

格式依循 [Keep a Changelog](https://keepachangelog.com/zh-TW/1.1.0/)，
版本號依循 [語意化版本](https://semver.org/lang/zh-TW/)。

## [未發布]

## [0.1.0] — 2026-09-21

第一個公開版本。

### 新增

- **選單列圖示**就是儀表：外弧＝5 小時窗口、內弧＝7 天窗口、底部的點＝幾個 agent 在跑。
  沒有讀數或讀數過期時**不上色**（單色代表「這個數字不可信」）。
- **有人在等你輸入**時圖示換成完全不同的形狀（琥珀色滿環 + 箭頭）並開始呼吸。
  琥珀色在這個 app 裡只有這一個意思。
- **完成訊號**：長工作結束後生物染成丁香紫，滿色 180 秒、退色到 600 秒。
- **面板**：額度三欄（5 小時 / 7 天 / 分模型）、session 列表、context 壓力、
  agent 樹與 workflow 進度、失敗計數。
- **通知**（T1 等你輸入 / T2 扇出排空 / T3 額度分級變化），含在場判斷
  （螢幕鎖定、螢幕休眠、閒置超過 5 分鐘就不出聲）與每小時三則的滾動預算。
- **statusline tee**：可安裝、可還原的 wrapper，把額度讀數從「16 小時可能不更新」
  變成秒級。只動 `settings.json` 裡一個字串，動手前留備份。
- **開機自動啟動**（`SMAppService`）。
- **偏好設定**四項：音效、「明早」幾點、context 黃/紅門檻、額度緊張門檻。
- **額度時間序列**（`usage-history.jsonl`），30 天保留。
- 一整套診斷指令（`--dump`、`--render-panel`、`--render`、`--render-icon`、
  `--trace-alerts`、`--probe-login` …）。

### 已知限制

- **Apple Silicon 專屬**，不出 Intel 版本。
- **沒有經過 Apple 公證** —— 作者只有免費 Apple ID。下載的 DMG 會被 Gatekeeper 擋，
  安裝步驟見 README。
- `minos` 是 macOS 14.0，但〔推論，非實測〕只在 macOS 27 上實際跑過。
- 純 Agent 扇出（不經 workflow）永遠不會觸發 T2 通知 —— 那種 run 沒有終結狀態可讀。
- 讀不到 Focus / 勿擾模式（TCC 不開放），所以在場判斷只看鎖定 / 休眠 / 閒置。
- osascript 送出的通知永遠被歸給「指令碼編輯器」，這是系統行為，改不了。
- **每日長條圖還沒畫。** 不是資料不夠：取樣是事件驅動的（不跑 Claude Code 就沒有點），
  而且 7 天窗口是滾動的、5 小時窗口每五小時歸零 —— 兩條線都不能直接差分成
  「今天用了多少」。「那根長條代表什麼」這個問題還沒有答案。

[未發布]: https://github.com/cookiesmonster7926/QuotaMonster/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/cookiesmonster7926/QuotaMonster/releases/tag/v0.1.0
