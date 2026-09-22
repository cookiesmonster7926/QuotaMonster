// 資料層。
//
// ⚠️ 這裡原本有一個 `public static let version = "0.1.0-stage0"`，而
// `Resources/Info.plist` 同時寫著 `0.1.0` —— **兩個版本字串，從 v0.1.0 出貨之前
// 就不一致**。它之所以沒有造成傷害，只是因為〔實測〕全 repo 沒有任何人讀它
// （`grep -rn "QuotaMonsterCore\.version" Sources/ Tests/` 零命中，也沒有 `--version` 旗標）。
//
// 拿掉而不是改對，理由是規矩 2：**版本只能有一個來源**，而那個來源必須是
// 真的會被用到的那一個（`Resources/Info.plist`，`make_app.sh` 逐字複製它、
// `make_dmg.sh` 用它命名 DMG）。留一個沒人讀的第二份，下一次改版只會再錯一次。
public enum QuotaMonsterCore {}
