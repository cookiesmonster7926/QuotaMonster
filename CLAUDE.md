# QuotaMonster

macOS 選單列 app（Swift 6 / AppKit / SwiftPM），看 Claude Code 的額度與 session。

## 接手時第一件事

**讀 `docs/quotamonster.md`。** 它有 32 條不可違反的規矩、16 條寫下來的拒絕、
27 處「曾經這樣想、後來被資料推翻」，每一條都附證據與這個 repo 為它付過的代價。

⚠️ **不要拿 `docs/build-log.md` 當現況。** 那是施工紀錄，裡面有已知是錯的敘述
（哪些錯了，列在 `docs/quotamonster.md` 第三節）。

## 驗收指令

```bash
bash scripts/test.sh                        # ⚠️ 不可以直接 swift test（見規矩 27）
rm -rf .build && swift build -c release     # 增量建置的 Build complete 是假象
bash scripts/make_app.sh                    # 組 .app 並裝到 ~/Applications
```

## 這個專案最容易踩的三個坑

1. **決策只能放 `QuotaMonsterCore`。** `QuotaMonsterApp` 沒有測試 target
   （`Package.swift` 只有一個 testTarget），放進去的判斷就永遠不會有測試。
2. **`nil` 一律是「不知道」，不是零。** 缺資料回 nil、畫「—」，
   絕對不要回 0%、0 秒或 `Date()`。而且「看到它、但它不在那個狀態」
   與「整個沒看到它」是兩件事，要分兩層處理。
3. **註解裡「實測」「代理量測」「推論」「文件說」是四件不同的事，不可以混用。**
   這個 repo 每一條 ⚠️ 都被下一個人當成實測結果在信。

## 診斷

`docs/quotamonster.md` 第四節有完整對照表（哪一支回答哪一個問題）。
⚠️ 配色一律用 `--dark` 檢查，而且**判配色要看 2x**（Retina 的選單列是 2x）。
