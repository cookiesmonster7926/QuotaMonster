import Testing
import Foundation
@testable import QuotaMonsterCore

/// 「還有多久重置」那一行的措辭。
///
/// ### 為什麼它必須只有一份
/// 〔code review 2026-09-23〕簡易版面自己寫了第二份，而兩份在**三個方向**漂開了：
///
/// 1. **字彙**：完整面板回「已重置」，簡易頁回「重置時間已過」。
/// 2. **契約**：`OutlookCaption.fiveHour` 的檔頭把 `resetText` 的集合寫死成
///    （`剩 1h 44m` / `已重置` / `" "`），而 `.exhausted` 分支 `guard resetText.hasPrefix("剩 ")`
///    就建在那個集合上。簡易頁餵進去的字串不在集合裡，於是恢復時間整個消失。
/// 3. **時鐘**：一份用 `Date()`、一份用 `store.lastRefresh`，同一個數字在兩頁差一分鐘。
///
/// ### ⚠️ 「剩不到一分鐘」不是「已經過了」
/// `WindowExpiry.accepts` 保證 `resetsAt > now`（已過的窗口在讀取時就被丟掉），
/// 所以「不足一分鐘」唯一的含意是**還剩幾十秒**。
/// 第二份把它判成「重置時間已過」，於是在窗口最後 60 秒會印出
/// 「重置時間已過 · 估 79%」—— 同一句話的兩半互相否定。
@Suite("ResetCaption — 倒數的措辭只有一份")
struct ResetCaptionTests {

    let now = Date(timeIntervalSince1970: 1_790_000_000)

    @Test("沒有重置時間就是空的 —— 不是「—」，那一格由數字自己說")
    func noResetTimeIsBlank() {
        #expect(ResetCaption.countdown(resetsAt: nil, now: now) == " ")
    }

    @Test("已經過了就說「已重置」")
    func pastIsAlreadyReset() {
        #expect(ResetCaption.countdown(resetsAt: now.addingTimeInterval(-60), now: now) == "已重置")
    }

    @Test("剛好同一刻也算已重置 —— 邊界倒向「已經發生」")
    func exactlyNowIsAlreadyReset() {
        #expect(ResetCaption.countdown(resetsAt: now, now: now) == "已重置")
    }

    @Test("⚠️ 剩不到一分鐘是「剩 0m」，不是「重置時間已過」")
    func underAMinuteIsStillRemaining() {
        // 這正是 code review 抓到的那一格：`WindowExpiry` 保證窗口還活著，
        // 所以這 30 秒是**未來**。說它已經過了，會和同一行後半的投射互相否定。
        #expect(ResetCaption.countdown(resetsAt: now.addingTimeInterval(30), now: now) == "剩 0m")
    }

    @Test("小時與分鐘")
    func hoursAndMinutes() {
        #expect(ResetCaption.countdown(resetsAt: now.addingTimeInterval(90 * 60), now: now) == "剩 1h 30m")
        #expect(ResetCaption.countdown(resetsAt: now.addingTimeInterval(30 * 60), now: now) == "剩 30m")
    }

    @Test("⚠️ 回傳值一定落在 `OutlookCaption` 記載的那個集合裡")
    func everyOutputSatisfiesTheOutlookContract() {
        // `OutlookCaption.fiveHour` 的 `.exhausted` 分支 `guard resetText.hasPrefix("剩 ")`
        // 就建在這個集合上。任何一個新的措辭跑出集合外，那個分支就會安靜地退化。
        let cases: [Date?] = [nil, now.addingTimeInterval(-1), now,
                              now.addingTimeInterval(1), now.addingTimeInterval(59),
                              now.addingTimeInterval(3600), now.addingTimeInterval(7 * 86400)]
        for c in cases {
            let s = ResetCaption.countdown(resetsAt: c, now: now)
            #expect(s == " " || s == "已重置" || s.hasPrefix("剩 "),
                    "跑出契約集合的字串：「\(s)」")
        }
    }

    @Test("餵進 OutlookCaption 之後，耗盡那一格說得出恢復時間")
    func theExhaustedBranchStillWorks() {
        // 這一則是上一則的「為什麼」：契約成立時 `.exhausted` 才講得出「N 後恢復」。
        let text = ResetCaption.countdown(resetsAt: now.addingTimeInterval(30), now: now)
        #expect(text.hasPrefix("剩 "))
    }
}
