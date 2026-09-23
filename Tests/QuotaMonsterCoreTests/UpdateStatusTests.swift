import Testing
import Foundation
@testable import QuotaMonsterCore

/// 「有沒有新版」的三態，以及面板要寫什麼。
///
/// ### ⚠️ 這裡最容易犯的錯只有一個
/// **把「問不到」畫成「你已經是最新的」。**
/// 那是這個 repo 的兩層規矩：看到它但它不在那個狀態（＝真的問到了、沒有新版）
/// 與整個沒看到它（＝連不上、被限流、回應解不出來）是兩件事。
/// 混在一起的後果是：一個永遠連不上的使用者，會永遠看到「你是最新的」。
@Suite("UpdateStatus")
struct UpdateStatusTests {

    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let current = ReleaseVersion("0.3.0")!

    func caption(_ s: UpdateStatus, lastSuccess: Date? = nil, now: Date? = nil) -> String? {
        UpdateCaption.text(s, lastSuccess: lastSuccess, now: now ?? self.now)
    }

    // ── 判斷 ───────────────────────────────────────────────────

    @Test("比自己新就是有新版")
    func newerIsAvailable() {
        let s = UpdateStatus.from(latestTag: "v0.4.0", current: current,
                                  isDraft: false, isPrerelease: false, url: "u")
        #expect(s == .available(ReleaseVersion("0.4.0")!, url: "u"))
    }

    @Test("一樣或更舊就是最新的 —— 這是**正面證據**，我們真的問到了")
    func sameOrOlderIsUpToDate() {
        for tag in ["v0.3.0", "v0.2.9", "v0.1.0"] {
            #expect(UpdateStatus.from(latestTag: tag, current: current,
                                      isDraft: false, isPrerelease: false, url: "u") == .upToDate)
        }
    }

    @Test("⚠️ 草稿與預覽版不算 —— 但那是「不知道」，不是「最新的」")
    func draftsAndPrereleasesAreUnknownNotUpToDate() {
        // 它們代表「這一次問到的東西不能拿來判斷」，不代表「沒有新版」。
        #expect(UpdateStatus.from(latestTag: "v0.4.0", current: current,
                                  isDraft: true, isPrerelease: false, url: "u")
                == .unknown(.draftOrPrerelease))
        #expect(UpdateStatus.from(latestTag: "v0.4.0", current: current,
                                  isDraft: false, isPrerelease: true, url: "u")
                == .unknown(.draftOrPrerelease))
    }

    @Test("⚠️ tag 解不出來是「不知道」，不是「最新的」")
    func anUnparseableTagIsUnknown() {
        #expect(UpdateStatus.from(latestTag: "nightly", current: current,
                                  isDraft: false, isPrerelease: false, url: "u")
                == .unknown(.unparseableTag("nightly")))
    }

    // ── 面板那一行 ─────────────────────────────────────────────

    @Test("有新版就說出來，而且說得出版本號")
    func availableSaysTheVersion() throws {
        let t = try #require(caption(.available(ReleaseVersion("0.4.0")!, url: "u")))
        #expect(t.contains("0.4.0"))
    }

    @Test("已經是最新的就不要佔版面 —— 沒有新聞不是新聞")
    func upToDateSaysNothing() {
        #expect(caption(.upToDate, lastSuccess: now) == nil)
    }

    @Test("⚠️ 剛連不上的時候也安靜 —— 一次失敗不值得打擾")
    func aSingleFailureIsQuiet() {
        #expect(caption(.unknown(.offline), lastSuccess: now.addingTimeInterval(-3600)) == nil)
    }

    @Test("⚠️ 但**一直**問不到就必須說 —— 沉默會被讀成「你是最新的」")
    func aLongOutageMustBeSaid() throws {
        let t = try #require(caption(.unknown(.offline),
                                     lastSuccess: now.addingTimeInterval(-10 * 86400)))
        #expect(t.contains("連不上") || t.contains("問不到") || t.contains("檢查"))
        // 而且不可以在這種時候說「最新」。
        #expect(!t.contains("最新"))
    }

    @Test("⚠️ 從來沒成功過、又過了很久，一樣要說")
    func neverSucceededAlsoCounts() {
        // lastSuccess == nil 不可以被當成「剛剛才成功」。
        #expect(caption(.unknown(.offline), lastSuccess: nil) != nil)
    }

    @Test("還沒檢查過的時候安靜 —— app 剛開機不該先道歉")
    func notCheckedYetIsQuiet() {
        #expect(caption(.unknown(.notCheckedYet), lastSuccess: nil) == nil)
    }

    // ── 什麼時候去問 ───────────────────────────────────────────

    @Test("從來沒問過就問")
    func neverCheckedMeansCheck() {
        #expect(UpdateCheck.shouldCheck(lastAttempt: nil, now: now))
    }

    @Test("剛問過就不要再問")
    func recentlyCheckedMeansWait() {
        #expect(!UpdateCheck.shouldCheck(lastAttempt: now.addingTimeInterval(-60), now: now))
    }

    @Test("過了間隔就再問一次")
    func afterTheIntervalCheckAgain() {
        let t = now.addingTimeInterval(-UpdateCheck.interval - 1)
        #expect(UpdateCheck.shouldCheck(lastAttempt: t, now: now))
    }

    @Test("⚠️ 未來的時間戳不可以讓它永遠不再檢查")
    func aFutureTimestampDoesNotWedgeIt() {
        // 時鐘往回跳、或狀態檔被手改 —— 這個 repo 已經為同一種不對稱付過三次代價
        // （StatusLineCacheReader / WindowExpiry / AgentActivity 都補了上界）。
        #expect(UpdateCheck.shouldCheck(lastAttempt: now.addingTimeInterval(86400), now: now))
    }

    @Test("間隔遠低於 GitHub 的限流 —— 那個數字是量到的")
    func theIntervalIsWellUnderTheRateLimit() {
        // 〔實測 2026-09-23〕未認證請求 `x-ratelimit-limit: 60`（每小時、每 IP）。
        #expect(UpdateCheck.interval >= 3600, "一小時問一次以上就開始逼近限流")
    }
}
