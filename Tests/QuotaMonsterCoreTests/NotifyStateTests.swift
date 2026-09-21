import Testing
import Foundation
@testable import QuotaMonsterCore

/// 跨重啟活下來的那一小塊。
///
/// **為什麼非存不可：** 這個 repo 已經為這件事付過一次代價 ——
/// `UsageHistory` 的註解裡寫著「上一筆是什麼放在記憶體裡，所以每個新行程都會
/// 覺得自己是第一次 —— 實測 app 重啟三次加兩支診斷指令，就寫出四行一模一樣的
/// 紀錄」。通知層的版本比四行重複的 JSONL 大聲得多。
///
/// 而 `mutedUntil` 根本不是觀測值，是**使用者直接下的指令**，它自己講明的
/// 時間跨度（「靜音到明早」約 12 小時）遠長於這個 app 的一次執行。
/// 丟掉它 = 在使用者明確要求安靜的時段裡出聲，正是設計文件點名要避免的那件事。
///
/// **什麼不存：** 60 秒去重窗與 4 秒合併窗。兩者都比任何一次重啟短，存了沒用，
/// 還要在三秒輪詢上多寫一次檔。
@Suite("NotifyState")
struct NotifyStateTests {

    let t0 = Date(timeIntervalSince1970: 1_789_660_000)
    func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    func temp() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("qm-notify-\(UUID().uuidString).json")
    }

    // ── 來回一趟 ───────────────────────────────────────────────

    @Test("存了再讀回來，兩邊一樣")
    func roundTrip() throws {
        let url = temp()
        // now 要一起給：save 會順手清掉已經過期的靜音，而 t0 是固定的過去時間。
        #expect(NotifyState.save(NotifyState(mutedUntil: at(3600)), to: url, now: t0) == true)
        let back = try #require(NotifyState.load(url))
        #expect(back.mutedUntil == at(3600))
    }

    @Test("沒有靜音時 mutedUntil 是 nil，不是某個過去的時間")
    func noMuteIsNil() throws {
        let url = temp()
        #expect(NotifyState.save(NotifyState(), to: url, now: t0) == true)
        let back = try #require(NotifyState.load(url))
        #expect(back.mutedUntil == nil)
    }

    // ── 壞掉的輸入 ─────────────────────────────────────────────

    @Test("檔案不存在回 nil，不丟錯")
    func missingFileIsNil() {
        #expect(NotifyState.load(temp()) == nil)
    }

    @Test("壞掉的 JSON 回 nil —— 當成沒有狀態，不要讓 app 起不來")
    func corruptFileIsNil() throws {
        let url = temp()
        try "{ 這不是 JSON".data(using: .utf8)!.write(to: url)
        #expect(NotifyState.load(url) == nil)
    }

    @Test("零位元組檔回 nil")
    func emptyFileIsNil() throws {
        let url = temp()
        try Data().write(to: url)
        #expect(NotifyState.load(url) == nil)
    }

    @Test("未知的鍵無害 —— 之後加欄位不可以讓舊檔整個讀不回來")
    func unknownKeysAreHarmless() throws {
        let url = temp()
        try #"{"mutedUntil":1789663600,"lastNotified":{},"somethingNew":42}"#
            .data(using: .utf8)!.write(to: url)
        let back = try #require(NotifyState.load(url))
        #expect(back.mutedUntil == at(3600))
    }

    // ── 不可以把 app 搞壞 ───────────────────────────────────────

    @Test("目錄不可寫時回 false，不丟錯也不 crash")
    func unwritableDirectoryReturnsFalse() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("qm-ro-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755],
                                                   ofItemAtPath: dir.path)
            try? FileManager.default.removeItem(at: dir)
        }
        #expect(NotifyState.save(NotifyState(), to: dir.appendingPathComponent("s.json")) == false)
    }

    // ── 自己把自己收乾淨 ────────────────────────────────────────

    @Test("已經拿掉的欄位不可以讓舊檔整個讀不回來")
    func fieldsRemovedInANewerVersionAreHarmless() throws {
        // 曾經存過 lastNotified，後來發現它是死的就拿掉了。
        // 磁碟上還留著那些檔案。
        let url = temp()
        try #"{"mutedUntil":1789663600,"lastNotified":{"S1":{"key":"a","at":1}}}"#
            .data(using: .utf8)!.write(to: url)
        let back = try #require(NotifyState.load(url))
        #expect(back.mutedUntil == at(3600))
    }

    @Test("已經過期的靜音在寫檔時就清掉，不用等有人來問")
    func expiredMuteIsDroppedOnWrite() throws {
        let url = temp()
        #expect(NotifyState.save(NotifyState(mutedUntil: at(-10)),
                                 to: url, now: t0) == true)
        let back = try #require(NotifyState.load(url))
        #expect(back.mutedUntil == nil)
    }

    // ── 路徑 ───────────────────────────────────────────────────

    @Test("路徑跟其他狀態放在一起，不散落")
    func pathSitsWithTheOtherState() {
        let home = URL(fileURLWithPath: "/Users/x")
        #expect(NotifyState.defaultURL(home: home).path
                == "/Users/x/Library/Application Support/QuotaMonster/notify-state.json")
    }
}

/// 手動靜音的兩個選項。**不自建安靜時段排程器** —— macOS Focus 已經做了，
/// 第二個排程器正是「明明開了勿擾卻在半夜三點響」的成因。
@Suite("MutePolicy")
struct MutePolicyTests {

    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Taipei")!
        return c
    }

    func date(_ iso: String) -> Date {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.date(from: iso)!
    }

    @Test("靜音一小時就是一小時")
    func oneHour() {
        let now = date("2026-09-18 22:15:00")
        #expect(MutePolicy.oneHour(from: now) == now.addingTimeInterval(3600))
    }

    @Test("晚上按「到明早」，解除在隔天早上八點")
    func tomorrowMorningFromNight() {
        #expect(MutePolicy.tomorrowMorning(from: date("2026-09-18 22:15:00"),
                                           calendar: calendar)
                == date("2026-09-19 08:00:00"))
    }

    @Test("凌晨三點按「到明早」，解除在**今天**早上八點 —— 不是再等 29 小時")
    func tomorrowMorningFromTheSmallHours() {
        // 這是這個函式唯一會被寫錯的地方：半夜三點的「明早」是五小時後，
        // 不是明天。天真的 +1 day 會讓使用者整個白天都是靜音的。
        #expect(MutePolicy.tomorrowMorning(from: date("2026-09-19 03:00:00"),
                                           calendar: calendar)
                == date("2026-09-19 08:00:00"))
    }

    @Test("早上七點五十九按下去，解除在一分鐘後 —— 邊界不做特例")
    func justBeforeMorning() {
        #expect(MutePolicy.tomorrowMorning(from: date("2026-09-19 07:59:00"),
                                           calendar: calendar)
                == date("2026-09-19 08:00:00"))
    }

    // ── 單鍵循環 ───────────────────────────────────────────────

    @Test("一顆按鈕循環三種狀態：關 → 1 小時 → 到明早 → 關")
    func theBellCyclesThroughThreeStates() {
        // ⚠️ 刻意不用 SwiftUI 的 Menu。理由與它們各自的分量見 MutePolicy.next
        // 的註解 —— 一個已證實（離屏渲染壞掉），一個未證實（transient popover）。
        // 循環鍵沒有第二個視窗，而且目前是哪一段一直看得見。
        let now = date("2026-09-18 22:15:00")
        let one = MutePolicy.next(from: nil, now: now, calendar: calendar)
        #expect(one == MutePolicy.oneHour(from: now))

        let morning = MutePolicy.next(from: one, now: now, calendar: calendar)
        #expect(morning == MutePolicy.tomorrowMorning(from: now, calendar: calendar))

        #expect(MutePolicy.next(from: morning, now: now, calendar: calendar) == nil)
    }

    @Test("已經過期的靜音當成沒有靜音 —— 下一下是「1 小時」而不是「到明早」")
    func anExpiredMuteRestartsTheCycle() {
        let now = date("2026-09-18 22:15:00")
        let expired = now.addingTimeInterval(-60)
        #expect(MutePolicy.next(from: expired, now: now, calendar: calendar)
                == MutePolicy.oneHour(from: now))
    }

    @Test("凌晨三點時「1 小時」比「到明早」短，順序仍然是 1 小時先")
    func theCycleOrderDoesNotDependOnWhichIsLonger() {
        // 半夜三點的「到明早」只有五小時，比一小時長；但清晨七點半的「到明早」
        // 只有三十分鐘，比一小時**短**。循環的順序是固定的語意順序，不是長度排序。
        let early = date("2026-09-19 07:30:00")
        let one = MutePolicy.next(from: nil, now: early, calendar: calendar)
        let morning = MutePolicy.next(from: one, now: early, calendar: calendar)
        #expect(morning! < one!)
    }

    @Test("早上八點整按下去，解除在隔天 —— 已經是早上了")
    func exactlyAtMorning() {
        #expect(MutePolicy.tomorrowMorning(from: date("2026-09-19 08:00:00"),
                                           calendar: calendar)
                == date("2026-09-20 08:00:00"))
    }
}
