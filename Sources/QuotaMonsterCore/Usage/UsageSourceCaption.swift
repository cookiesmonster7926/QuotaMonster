import Foundation

/// 面板額度區塊那兩段字：**這個數字為什麼是這個數字，或為什麼沒有數字。**
///
/// ### 為什麼在 Core
/// `QuotaMonsterApp` 沒有測試（它碰 AppKit），而這裡的風險全在字串上 ——
/// 尤其是「叫一個已經裝好 tee 的人再去裝一次」這種謊。
/// 放在這裡，「tee 有在寫就不准說沒裝」是一個 `#expect`，不是一句承諾。
///
/// ### ⚠️ `~/.claude.json` 這個來源已經死了
/// 〔實測 2026-09-21，單一機器〕那個檔案還在被 Claude Code 持續重寫
/// （mtime 是當下），但 `cachedUsageUtilization.fetchedAtMs` **凍在 3.9 天前**。
/// repo 舊文件寫「實測可以整整 16 小時不更新」—— 現在是根本不再更新。
/// 把 statusline 快取目錄移開實跑 `--dump`：兩個窗口都變成「沒有讀數」。
///
/// 後果：**沒有 statusline tee 就完全沒有額度數字**，所以文案不可以把 tee
/// 講成「可選的加強」。它是唯一的來源。
///
/// ### 為什麼拆成兩個函式
/// 角落那行註腳右對齊、10pt，塞得下的預算很小（見 `OutlookCaption` 檔頭那段
/// 寬度預算的實測）。一行安裝指令塞進去會把註腳擠到看不清楚。
/// 所以註腳保持短，指令走 `setupHint`，由面板放在額度欄位底下的空位。
public enum UsageSourceCaption {

    /// 角落那一行。**短。**
    public static func text(usage: UsageSnapshot?, source: UsageSource?,
                            statusLinePayloadCount: Int) -> String {
        guard let usage else {
            // ⚠️ 這裡原本只回「無讀數」，而那是新使用者第一眼唯一看得到的東西。
            return statusLinePayloadCount > 0
                ? "無讀數 · tee 有在寫，但那些 payload 還沒帶到額度"
                : "無讀數 · 沒裝 statusline tee"
        }

        let age: String
        switch usage.freshness {
        case .live:          age = "剛更新"
        case .aging(let m):  age = "\(m) 分鐘前"
        case .expired:       age = "已過期"
        }

        switch source {
        case .statusLine:
            // tee 的「舊」代表「你沒在用」，不代表數字不準。
            return usage.freshness == .expired ? "\(age) · 已經一小時沒有 session 動過" : age
        case .claudeJSON:
            guard usage.freshness == .expired else { return "\(age) · 來自 ~/.claude.json" }
            // ⚠️ tee 明明一秒前才寫過檔，卻說「沒裝 statusline tee」是最糟的謊：
            // 使用者會去重裝一個已經裝好的東西。
            return statusLinePayloadCount > 0
                ? "\(age) · tee 有在寫，但那些 payload 還沒帶到額度"
                : "\(age) · 沒裝 statusline tee，這份快取不會即時更新"
        case nil:
            return age
        }
    }

    /// 額度欄位底下的空狀態提示。**只有在使用者真的該動手時才回非 nil。**
    ///
    /// 「該動手」＝沒有任何活的讀數，而且快取目錄裡一個 payload 都沒有。
    /// 只要 tee 有在寫，就一律回 nil —— 那時候問題不在安裝，叫他重裝只會更糟。
    /// - Parameter installCommand: 要印給使用者照做的那一行。
    ///
    ///   ⚠️ **由呼叫端給，Core 不可以自己編。**〔code review 2026-09-22〕
    ///   這裡原本寫死「`bash scripts/install_statusline_tee.sh --apply`」——
    ///   那是 repo 相對路徑，而**下載 DMG 的人沒有 repo**（實測 `.app` 裡
    ///   只有 `AppIcon.icns`）。新使用者唯一會看到的指引因此不可執行。
    ///
    ///   修法是把 `scripts/` 打進 bundle，由 App 層解析出真正的絕對路徑。
    ///   Core 不知道 bundle 是什麼，所以那個字串只能從外面進來。
    public static func setupHint(usage: UsageSnapshot?, source: UsageSource?,
                                 statusLinePayloadCount: Int,
                                 installCommand: String) -> String? {
        guard statusLinePayloadCount == 0 else { return nil }
        let hasLiveReading = usage != nil && usage?.freshness != .expired
        guard !hasLiveReading else { return nil }
        return "額度數字的唯一來源是 statusline tee（~/.claude.json 已經不再更新）。"
             + "安裝：\(installCommand)"
    }
}
