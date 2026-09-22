import Testing
import Foundation
@testable import QuotaMonsterCore

@Suite("Preferences — 使用者直接調過的那幾格")
struct PreferencesTests {

    func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("qm-prefs-\(UUID().uuidString)")
            .appendingPathComponent("preferences.json")
    }

    @Test("⚠️ 沒調過的欄位在磁碟上不存在 —— 檔案是 `{}`")
    func untouchedPreferencesWriteAnEmptyObject() throws {
        // 這是整個設計最重要的一條：預設值**不可以**被寫進檔案。
        // 寫進去的話，新的量測把預設從 90 改成 120 時，一個從來沒動過設定的
        // 使用者會被永遠釘在舊值上 —— 而他不知道自己「設定過」。
        let u = tempURL()
        #expect(Preferences.save(.empty, to: u))
        #expect(try String(contentsOf: u, encoding: .utf8) == "{}")
    }

    @Test("只調了一格，就只有那一格上磁碟")
    func onlyTouchedFieldsArePersisted() throws {
        let u = tempURL()
        #expect(Preferences.save(Preferences(morningHour: 9), to: u))
        let text = try String(contentsOf: u, encoding: .utf8)
        #expect(text.contains("morningHour"))
        #expect(!text.contains("contextYellow"))
        #expect(!text.contains("alertSound"))
    }

    @Test("讀回來要一模一樣")
    func roundTrips() throws {
        let u = tempURL()
        let p = Preferences(alertSound: .named("Hero"), morningHour: 7,
                            contextYellow: 60, contextRed: 85)
        #expect(Preferences.save(p, to: u))
        #expect(Preferences.load(u) == p)
    }

    @Test("「不出聲」是一個真正的選擇，不是一個空字串")
    func silentIsItsOwnCase() throws {
        // 用 "" 當哨兵的話，「沒設定」「不出聲」「設了一個叫空字串的音效」
        // 三件事會塌縮成一格 —— 而這個 repo 為那種塌縮付過代價。
        let u = tempURL()
        #expect(Preferences.save(Preferences(alertSound: .silent), to: u))
        #expect(Preferences.load(u)?.alertSound == .silent)
    }

    @Test("壞檔、空檔、不存在一律回 nil，不丟錯")
    func badFilesAreNil() throws {
        #expect(Preferences.load(tempURL()) == nil)
        let u = tempURL()
        try FileManager.default.createDirectory(
            at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{ 這不是 JSON".utf8).write(to: u)
        #expect(Preferences.load(u) == nil)
    }

    @Test("未知的鍵無害 —— 舊檔與新版都要讀得回來")
    func unknownKeysAreHarmless() throws {
        let u = tempURL()
        try FileManager.default.createDirectory(
            at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"morningHour":9,"somethingFromTheFuture":42}"#.utf8).write(to: u)
        #expect(Preferences.load(u)?.morningHour == 9)
    }

    // ── 夾限：擋的是手改 JSON，不是 UI ──────────────────────────

    @Test("手改成荒謬的小時會被夾回來")
    func morningHourIsClamped() {
        #expect(Preferences(morningHour: 99).sanitised().morningHour == 23)
        #expect(Preferences(morningHour: -5).sanitised().morningHour == 0)
        #expect(Preferences(morningHour: 9).sanitised().morningHour == 9)
    }

    @Test("⚠️ 黃 ≥ 紅是夾不回來的錯 —— 整組丟掉，不要猜他想要什麼")
    func contradictoryThresholdsAreDroppedNotGuessed() {
        // 夾成「黃 = 紅 − 1」是在替使用者發明一個他沒有選過的設定，
        // 而一組互相矛盾的門檻比沒有設定更糟：顏色會在一個他預期不到的
        // 百分比上變，而他以為那是他設的。
        let bad = Preferences(contextYellow: 90, contextRed: 70).sanitised()
        #expect(bad.contextYellow == nil)
        #expect(bad.contextRed == nil)
        // 合理的那一組原樣留著。
        let good = Preferences(contextYellow: 60, contextRed: 85).sanitised()
        #expect(good.contextYellow == 60)
        #expect(good.contextRed == 85)
    }

    @Test("只設了一邊的門檻仍然收 —— 另一邊用預設")
    func oneSidedThresholdIsKept() {
        #expect(Preferences(contextYellow: 55).sanitised().contextYellow == 55)
        #expect(Preferences(contextRed: 95).sanitised().contextRed == 95)
    }

    // ── 額度門檻 ───────────────────────────────────────────────

    @Test("⚠️ 額度門檻要嘛兩個都有、要嘛整組丟掉")
    func quotaThresholdsAreAllOrNothing() {
        // 只設一邊會讓另一邊用預設，而那兩個數的意義是**相對的** ——
        // 「critical 5% + 預設 tight 50%」不是使用者要的任何一種設定。
        #expect(Preferences(quotaCritical: 0.05).sanitised().quotaCritical == nil)
        #expect(Preferences(quotaTight: 0.35).sanitised().quotaTight == nil)
        let both = Preferences(quotaCritical: 0.05, quotaTight: 0.35).sanitised()
        #expect(both.quotaCritical == 0.05)
        #expect(both.quotaTight == 0.35)
    }

    @Test("critical ≥ tight 在型別上就不存在 —— 不是回一個表示不出來的狀態")
    func quotaThresholdsCannotCross() {
        // 交叉的話 tight 那一格**永遠不可達**，畫面上只看得到「藍直接跳紅」，
        // 而沒有人會把那個現象歸因到設定。
        let crossed = QuotaThresholds(critical: 0.60, tight: 0.30)
        #expect(crossed.critical < crossed.tight)
    }

    @Test("讀檔的時候就夾 —— 手改的 JSON 進不到 UI")
    func loadSanitises() throws {
        let u = tempURL()
        try FileManager.default.createDirectory(
            at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"morningHour":99,"contextYellow":90,"contextRed":70}"#.utf8).write(to: u)
        let p = try #require(Preferences.load(u))
        #expect(p.morningHour == 23)
        #expect(p.contextYellow == nil)
    }
}

/// 圖表樣式 —— 使用者 2026-09-22 選的「兩種都做、可切換」。
@Suite("偏好 — 圖表樣式")
struct ChartStylePreferenceTests {
    @Test("預設是長條圖 —— 使用者原本要的就是「每天多少」")
    func defaultIsDaily() {
        #expect(ChartStyle.standard == .daily)
        #expect(Preferences().chartStyle == nil, "沒調過就不該出現在磁碟上（規矩 2）")
    }

    @Test("兩種都在，而且各自有名字")
    func bothStylesExist() {
        #expect(ChartStyle.allCases.count == 2)
        #expect(ChartStyle.allCases.allSatisfy { !$0.label.isEmpty })
    }

    @Test("存得進去也讀得回來")
    func roundTrips() throws {
        var p = Preferences()
        p.chartStyle = .cumulative
        let data = try JSONEncoder().encode(p.sanitised())
        #expect(try JSONDecoder().decode(Preferences.self, from: data).chartStyle == .cumulative)
    }

    @Test("⚠️ 沒調過的欄位不可以出現在 JSON 裡（規矩 2 的第二個條件）")
    func untouchedFieldIsAbsentFromDisk() throws {
        let json = String(decoding: try JSONEncoder().encode(Preferences().sanitised()), as: UTF8.self)
        #expect(json.contains("chartStyle") == false,
                "磁碟上出現預設值，新的量測改了預設他就不會跟著走")
    }
}
