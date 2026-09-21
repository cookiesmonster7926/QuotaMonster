import Testing
import Foundation
@testable import QuotaMonsterCore

/// 選單列圖示的顏色政策（2026-09-18 使用者決定改）。
///
/// 原本：顏色專屬於「有人在等你」，其他一律單色 template。
/// 現在：平常就依剩餘額度上色（綠 / 黃 / 紅）。
///
/// ⚠️ 兩條不可妥協的規則：
///   - **沒有讀數不上色。** 綠色代表「還很寬裕」，對一個不知道的值塗綠色是說謊。
///   - **過期的讀數也不上色。** 同上，而且過期本來就要降調。
///     這同時保留了第三種視覺狀態：單色 = 這個數字不可信。
///
/// 警示狀態不靠顏色區分 —— 它是**完全不同的形狀**（滿環 + 箭頭，而非生物 + 雙弧），
/// 而且是唯一會呼吸的狀態。所以平常上色不會讓它失去辨識度。
@Suite("QuotaTier")
struct QuotaTierTests {

    func state(five: Double?, seven: Double? = 0.9, blocked: Int = 0,
               freshness: Freshness = .live) -> GlyphState {
        GlyphState(fiveHourRemaining: five, sevenDayRemaining: seven,
                   runningAgents: 0, blockedSessions: blocked,
                   exhausted: false, freshness: freshness)
    }

    @Test("剩很多是綠的")
    func plentyIsComfortable() {
        #expect(state(five: 0.80).quotaTier == .comfortable)
    }

    @Test("剩一半以下轉黃")
    func halfIsTight() {
        #expect(state(five: 0.50).quotaTier == .tight)
        #expect(state(five: 0.51).quotaTier == .comfortable)
    }

    @Test("剩不到兩成轉紅")
    func underTwentyIsCritical() {
        #expect(state(five: 0.19).quotaTier == .critical)
        #expect(state(five: 0.20).quotaTier == .tight)
    }

    @Test("兩個窗口取比較緊的那一個 —— 你在意的是先撞到哪一道牆")
    func scarcestWindowWins() {
        #expect(state(five: 0.90, seven: 0.10).quotaTier == .critical)
        #expect(state(five: 0.10, seven: 0.90).quotaTier == .critical)
    }

    @Test("完全沒有讀數就不上色 —— 對不知道的值塗綠色是說謊")
    func noReadingMeansNoColour() {
        #expect(state(five: nil, seven: nil).quotaTier == nil)
    }

    @Test("過期的讀數也不上色")
    func expiredMeansNoColour() {
        #expect(state(five: 0.80, freshness: .expired).quotaTier == nil)
    }

    @Test("aging 還算數 —— 它只是有點舊，不是不可信")
    func agingStillGetsColour() {
        #expect(state(five: 0.80, freshness: .aging(minutes: 23)).quotaTier == .comfortable)
    }

    // ── 門檻只能有一個定義 ────────────────────────────────────────
    //
    // 選單列圖示與面板的進度條要用同一套顏色，所以門檻不可以各判一次。
    // 兩邊都走 QuotaTier.forRemaining。

    @Test("forRemaining 的門檻與 GlyphState.quotaTier 完全一致 —— 用**非預設**的門檻")
    func thresholdsHaveASingleDefinition() {
        // ⚠️ **這一則以前餵的是預設值，所以它是空的。**
        // 門檻變成可調之後，「兩邊都吃預設」一定相等 —— 那證明不了任何事。
        // 真正要釘的是「使用者調過之後兩邊仍然一致」，所以這裡必須餵一組
        // **不是預設**的門檻，而且要讓它們落在與預設不同的百分比上。
        let custom = QuotaThresholds(critical: 0.05, tight: 0.35)
        #expect(custom != .standard)
        for pct in stride(from: 0, through: 100, by: 1) {
            let remaining = Double(pct) / 100
            let direct = QuotaTier.forRemaining(remaining, thresholds: custom)
            let viaState = GlyphState(
                fiveHourRemaining: remaining, sevenDayRemaining: nil,
                runningAgents: 0, blockedSessions: 0, exhausted: false,
                freshness: .live, quotaThresholds: custom).quotaTier
            #expect(direct == viaState, "剩 \(pct)% 時兩邊判得不一樣")
        }
        // 而且那組門檻真的改變了結果 —— 否則上面的迴圈在一個
        // 「quotaTier 永遠回預設」的實作上也會過。
        let at10 = GlyphState(
            fiveHourRemaining: 0.10, sevenDayRemaining: nil,
            runningAgents: 0, blockedSessions: 0, exhausted: false,
            freshness: .live, quotaThresholds: custom).quotaTier
        #expect(at10 == .tight, "剩 10% 在 custom 下應該是 tight，在預設下才是 critical")
        #expect(QuotaTier.forRemaining(0.10, thresholds: .standard) == .critical)
    }

    @Test("T3 與圖示用同一組門檻 —— 額度通知在使用者調過的那一刻響")
    func thirdTierFollowsTheUserThresholds() throws {
        // 這是那個「非顯而易見的第二個消費者」：T3 是在分級**變了的那一刻**發的。
        // 使用者把 critical 調到 0.05，紅色警告也跟著晚到剩 5% 才響 ——
        // 這一則釘住引擎真的拿到了同一組門檻（而不是安靜地用預設）。
        let custom = QuotaThresholds(critical: 0.05, tight: 0.35)
        var e = NotificationEngine(quotaThresholds: custom)
        let t0 = Date(timeIntervalSince1970: 1_789_660_000)
        func input(_ usedPercent: Int) -> NotificationInput {
            NotificationInput(sessions: [], trees: [:],
                              usage: UsageSnapshot(
                                  fiveHour: UsageWindow(percent: usedPercent, resetsAt: nil),
                                  sevenDay: nil, perModel: [:],
                                  freshness: .live, fetchedAt: t0),
                              presence: .atKeyboard)
        }
        // 剩 40% → comfortable（預設下也是）。
        _ = e.update(input(60), now: t0)
        _ = e.flush(now: t0.addingTimeInterval(5))
        // 剩 10%：預設會判 critical，custom 只判 tight —— 所以這是一次
        // comfortable → tight 的降級，該發一則。
        _ = e.update(input(90), now: t0.addingTimeInterval(10))
        let events = e.flush(now: t0.addingTimeInterval(20))
        guard case .quotaTier(let q) = try #require(events.first) else {
            Issue.record("不是 quotaTier 事件"); return
        }
        #expect(q.to == .tight, "引擎用的不是使用者那組門檻（預設下這裡會是 critical）")
    }

    @Test("forRemaining 的邊界")
    func forRemainingBoundaries() {
        #expect(QuotaTier.forRemaining(0.51, thresholds: .standard) == .comfortable)
        #expect(QuotaTier.forRemaining(0.50, thresholds: .standard) == .tight)
        #expect(QuotaTier.forRemaining(0.20, thresholds: .standard) == .tight)
        #expect(QuotaTier.forRemaining(0.19, thresholds: .standard) == .critical)
        #expect(QuotaTier.forRemaining(0.0, thresholds: .standard) == .critical)
    }

    // ── template 與否 ─────────────────────────────────────────────

    @Test("有顏色就不能再當 template —— template 只看 alpha，顏色會被丟掉")
    func colouredStatesAreNotTemplates() {
        #expect(state(five: 0.80).usesTemplateRendering == false)
    }

    @Test("沒有讀數時仍然是 template，才能跟著選單列自動翻黑白")
    func unknownStaysTemplate() {
        #expect(state(five: nil, seven: nil).usesTemplateRendering == true)
    }

    @Test("警示狀態永遠不是 template（既有行為，不可退步）")
    func alertIsNeverATemplate() {
        #expect(state(five: nil, seven: nil, blocked: 1).usesTemplateRendering == false)
        #expect(state(five: 0.80, blocked: 1).usesTemplateRendering == false)
    }
}
