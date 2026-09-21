import Foundation

/// 額度的鬆緊程度，決定選單列圖示的顏色。
///
/// 配色是 **藍 → 綠 → 紅**（使用者 2026-09-18 指定），不是常見的綠→黃→紅。
/// ⚠️ **黃色不可以加回來。** 黃／琥珀是「要你輸入」專屬的顏色，
/// 拿去表示額度多寡會把唯一有時限的訊號稀釋掉。
/// 實際色值在 `GlyphRenderer.tierColour`。
public enum QuotaTier: Equatable, Sendable {
    /// 剩超過一半。畫成藍色。
    case comfortable
    /// 剩一半以下。畫成綠色。
    case tight
    /// 剩不到兩成。畫成紅色。
    case critical

    /// 從「剩餘比例 0…1」判斷分級。
    ///
    /// ⚠️ **判分級只能在這裡發生。** 選單列圖示與面板的三條進度條用的是同一套
    /// 顏色，各判一次就會在某個邊界上漂開 —— 而且那種不一致沒有人會馬上發現。
    ///
    /// ⚠️ **`thresholds` 刻意不給預設值。** 這一格是使用者可以調的
    /// （`Preferences.quotaCritical` / `.quotaTight`），而給了預設值之後，
    /// 任何一個忘了傳的消費者會**安靜地**用預設 —— 於是面板的條在 5% 轉紅、
    /// 選單列圖示還是 20% 轉紅、T3 在 5% 才響，**零編譯錯誤**。
    /// 不給預設值，漏接就是編譯錯誤。理由與 `Presence` 的三個參數同一條。
    public static func forRemaining(_ remaining: Double,
                                    thresholds: QuotaThresholds) -> QuotaTier {
        if remaining < thresholds.critical { return .critical }
        if remaining <= thresholds.tight { return .tight }
        return .comfortable
    }

    /// 從「已使用的百分比 0…100」判斷分級。面板拿到的是已使用，圖示拿到的是剩餘。
    public static func forUsed(percent: Int, thresholds: QuotaThresholds) -> QuotaTier {
        forRemaining(1 - Double(percent) / 100, thresholds: thresholds)
    }
}

/// 選單列標記要畫出來的完整狀態。純資料，沒有繪圖相依。
public struct GlyphState: Equatable, Sendable {
    /// 5 小時窗口**剩餘**比例 0…1。nil 代表不知道（與 0 完全不同）。
    public let fiveHourRemaining: Double?
    /// 7 天窗口剩餘比例 0…1。
    public let sevenDayRemaining: Double?
    /// 確定在跑的 agent 數。
    public let runningAgents: Int
    /// 正在等你回覆的 session 數。
    public let blockedSessions: Int
    /// 額度是否已耗盡（任一窗口歸零）。
    public let exhausted: Bool
    /// 讀數的新鮮度 —— 過期時整個標記要降調，不可假裝是現值。
    public let freshness: Freshness
    /// 剛剛有一輪講完了。見 `FinishGlow`。
    public let finishGlow: FinishGlow
    /// 額度分級的兩個邊界。使用者可以調，見 `QuotaThresholds`。
    ///
    /// ⚠️ **這是一個儲存欄位，不是從外面每次傳進來的參數。**
    /// `quotaTier` 是一個沒有參數的 computed property，而它有兩個消費者
    /// （`GlyphRenderer` 的上色與 `usesTemplateRendering`）——
    /// 沒有這個欄位，那條路就永遠只拿得到預設值。
    public let quotaThresholds: QuotaThresholds

    /// ⚠️ `finishGlow` **給預設值**，與 `Presence` 那條「不給預設值買到編譯錯誤」
    /// 刻意不同：那一條適用於**漏接會出錯**的欄位，而這一個漏接的後果是「不亮」。
    /// 給預設值讓五個既有建構點與八個 `from` 呼叫點一行都不用改。
    public init(fiveHourRemaining: Double?, sevenDayRemaining: Double?,
                runningAgents: Int, blockedSessions: Int,
                exhausted: Bool, freshness: Freshness,
                finishGlow: FinishGlow = .none,
                quotaThresholds: QuotaThresholds = .standard) {
        self.fiveHourRemaining = fiveHourRemaining
        self.sevenDayRemaining = sevenDayRemaining
        self.runningAgents = runningAgents
        self.blockedSessions = blockedSessions
        self.exhausted = exhausted
        self.freshness = freshness
        self.finishGlow = finishGlow
        self.quotaThresholds = quotaThresholds
    }

    /// 換一個完成訊號，其餘照舊。
    public func with(finishGlow: FinishGlow) -> GlyphState {
        GlyphState(fiveHourRemaining: fiveHourRemaining, sevenDayRemaining: sevenDayRemaining,
                   runningAgents: runningAgents, blockedSessions: blockedSessions,
                   exhausted: exhausted, freshness: freshness, finishGlow: finishGlow,
                   quotaThresholds: quotaThresholds)
    }

    /// 有人在等你 —— 唯一有時限的狀態，壓過一切。
    public var isAlerting: Bool { blockedSessions > 0 }

    public var posture: GlyphGeometry.CreaturePosture {
        GlyphGeometry.creaturePosture(agents: runningAgents, exhausted: exhausted)
    }

    /// 依剩餘額度決定的顏色分級。**沒有可信讀數時回 nil —— 那時候不上色。**
    ///
    /// 取兩個窗口裡比較緊的那一個：你在意的是先撞到哪一道牆。
    ///
    /// ⚠️ 過期的讀數回 nil，不是回一個顏色。綠色代表「還很寬裕」，
    /// 對一個你自己都知道不可信的數字塗綠色是說謊。這同時保留了第三種
    /// 視覺狀態：**單色 = 這個數字不可信**。
    public var quotaTier: QuotaTier? {
        guard freshness != .expired else { return nil }
        let scarcest = [fiveHourRemaining, sevenDayRemaining].compactMap { $0 }.min()
        guard let scarcest else { return nil }
        return .forRemaining(scarcest, thresholds: quotaThresholds)
    }

    /// 只有「沒有可信讀數、也沒人在等你」時才走 template image ——
    /// AppKit 的 template 只看 alpha channel，會把顏色整個丟掉。
    ///
    /// 走 template 的好處是淺色列、深色列自動翻色；不走的時候繪製端必須自己
    /// 拿一個會跟著選單列外觀變的墨色（見 `StatusItemController.ink`）。
    ///
    /// 警示狀態不靠顏色區分 —— 它是**完全不同的形狀**（滿環 + 箭頭，
    /// 而不是生物 + 雙弧），而且是唯一會呼吸的狀態。
    /// 生物身上那一點丁香紫 —— **有人在等你的時候整批丟掉**。
    ///
    /// 計畫書寫「有人被擋住時完成訊號整批丟掉」，這裡是它唯一的落點。
    /// ⚠️ 做成 computed property 而不是在管線某處降級，是為了讓
    /// 「琥珀與丁香同時出現」在**型別上**不可表示 —— 靠每個呼叫端記得判一次，
    /// 兩份判斷遲早會在某個邊界上漂開（`QuotaTier.forRemaining` 的檔頭就是
    /// 為這件事寫的）。
    ///
    /// **丟掉不是排隊**：警示結束之後不會補一次眨眼。那一輪的完成訊息
    /// 在琥珀亮著的時候就已經過去了。
    public var creatureGlow: FinishGlow { isAlerting ? .none : finishGlow }

    /// 生物要怎麼填色。
    public enum CreatureFill: Equatable, Sendable {
        /// 平常：墨色，過期讀數時降到 0.45。
        case ink(alpha: Double)
        /// 剛完成：丁香紫。
        case glow(FinishGlow)
    }

    /// ⚠️ 丁香紫**蓋過**過期讀數那個 0.45 的降調。
    /// 兩個訊號都在講「這個數字／這件事的狀態」，但完成是有時限的那一個，
    /// 而且退色版本身就是靠**混向墨色**做出來的 —— 再乘一次 alpha 會變成
    /// 兩套衰減疊在一起，沒有人讀得出來。
    public var creatureFill: CreatureFill {
        creatureGlow != .none
            ? .glow(creatureGlow)
            : .ink(alpha: freshness == .expired ? 0.45 : 1.0)
    }

    /// ⚠️ 第三個條件：生物染了丁香紫就不可以走 template ——
    /// AppKit 的 template 只看 alpha channel，會把顏色整個丟掉，
    /// 於是丁香紫會**安靜地**變成墨色。
    public var usesTemplateRendering: Bool {
        !isAlerting && quotaTier == nil && creatureGlow == .none
    }

    /// 從真實資料組出狀態。
    /// ⚠️ `thresholds` **不給預設值** —— 這是唯一的 production 建構路徑，
    /// 漏接就等於選單列與面板用不同的門檻判色。
    public static func from(usage: UsageSnapshot?, sessions: [LiveSession],
                            runningAgents: Int,
                            thresholds: QuotaThresholds) -> GlyphState {
        // 資料層給的是「已使用」，標記畫的是「剩餘」。轉換只在這裡發生一次。
        let five = usage?.fiveHour.map { 1.0 - Double($0.percent) / 100.0 }
        let seven = usage?.sevenDay.map { 1.0 - Double($0.percent) / 100.0 }
        return GlyphState(
            fiveHourRemaining: five,
            sevenDayRemaining: seven,
            runningAgents: runningAgents,
            blockedSessions: sessions.count { $0.needsHuman },
            exhausted: (five.map { $0 <= 0 } ?? false) || (seven.map { $0 <= 0 } ?? false),
            freshness: usage?.freshness ?? .expired,
            quotaThresholds: thresholds
        )
    }
}
