import Testing
import Foundation
@testable import QuotaMonsterCore

// ═══════════════════════════════════════════════════════════════
//  T1：有人在等你
// ═══════════════════════════════════════════════════════════════

/// T1 是整個 app 裡唯一有時限的訊號，所以它也是唯一可以打斷你的訊號。
/// 這組測試釘住的不是「會不會發」，而是**什麼時候不發** ——
/// 一個會在錯的時候喊的通知，比沒有通知更糟，因為它會訓練你忽略它。
///
/// 形狀照抄 `BreathController`：純 struct、時間用參數注入、狀態自己帶。
/// 兩處刻意不同：回傳 `[NotificationEvent]` 而不是 `Bool`（同一拍可能同時有
/// session A 的 T1 與 workflow B 的 T2），狀態是 keyed map 而不是純量。
/// 測試用的兩種在場狀態。
///
/// `away` 用的是 2026-09-19 那次實測抓到的真實數字：
/// `T2 · 看得到浮窗嗎 false（鎖定 true 螢幕睡 true 閒置 866s）`。
extension Presence {
    static let atKeyboard = Presence(screenLocked: false, screensAsleep: false,
                                     idleSeconds: 0)
    static let away = Presence(screenLocked: true, screensAsleep: true,
                               idleSeconds: 866)
}

@Suite("NotificationEngine — T1 有人在等你")
struct NotificationT1Tests {

    let t0 = Date(timeIntervalSince1970: 1_789_660_000)
    func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    // ── fixture ────────────────────────────────────────────────

    func session(_ id: String, status: SessionStatus, statusAt: Date?,
                 pid: Int32 = 4242, cwd: String = "/Users/x/Antigravity/usage") -> LiveSession {
        LiveSession(session: ClaudeSession(
            pid: pid, sessionId: id, cwd: cwd,
            startedAt: t0.addingTimeInterval(-3600), status: status,
            name: "usage-c9", version: "2.1.274", kind: "interactive",
            entrypoint: "cli", updatedAt: statusAt, statusUpdatedAt: statusAt))
    }

    func input(_ sessions: [LiveSession], presence: Presence = .atKeyboard)
    -> NotificationInput {
        NotificationInput(sessions: sessions, trees: [:], usage: nil, presence: presence)
    }

    /// 走過「先看到不等待、再看到等待」這條真實路徑。
    /// 第一次觀測不發通知是規則，不是 bug，所以每個測試都得先過這一關。
    func engineWitnessing(_ id: String = "S1") -> NotificationEngine {
        var e = NotificationEngine()
        _ = e.update(input([session(id, status: .busy, statusAt: at(-10))]), now: at(-10))
        return e
    }

    // ── 什麼時候不發 ───────────────────────────────────────────

    @Test("第一次觀測到的等待不發通知 —— 我們沒有見證它進入等待")
    func firstObservationNeverAlerts() {
        var e = NotificationEngine()
        let events = e.update(
            input([session("S1", status: .waiting(.inputNeeded), statusAt: at(0))]), now: at(0))
        #expect(events.isEmpty)
    }

    @Test("啟動時三個 session 都在等，也一個都不發 —— 這是啟動尖叫的來源")
    func launchWithManyWaitingIsSilent() {
        var e = NotificationEngine()
        let events = e.update(input([
            session("S1", status: .waiting(.inputNeeded), statusAt: at(0)),
            session("S2", status: .waiting(.permissionPrompt), statusAt: at(0)),
            session("S3", status: .waiting(.inputNeeded), statusAt: at(0)),
        ]), now: at(0))
        #expect(events.isEmpty)
    }

    @Test("一直在等的狀態不會每三秒發一次")
    func steadyWaitingDoesNotRepeat() {
        var e = engineWitnessing()
        let s = session("S1", status: .waiting(.inputNeeded), statusAt: at(0))
        _ = e.update(input([s]), now: at(0))
        _ = e.flush(now: at(5))                       // 第一次真的發出去
        for t in stride(from: 8.0, to: 200.0, by: 3.0) {
            #expect(e.update(input([s]), now: at(t)).isEmpty)
            #expect(e.flush(now: at(t)).isEmpty)
        }
    }

    @Test("同一個 now 連呼叫兩次只會發一次 —— refresh() 有六個呼叫點")
    func idempotentWithinOneInstant() {
        var e = engineWitnessing()
        let s = session("S1", status: .waiting(.inputNeeded), statusAt: at(0))
        _ = e.update(input([s]), now: at(0))
        _ = e.update(input([s]), now: at(0))
        let events = e.flush(now: at(5))
        #expect(events.count == 1)
    }

    // ── 什麼時候發 ─────────────────────────────────────────────

    @Test("見證它進入等待 —— 過了合併視窗就發一次")
    func witnessedTransitionAlertsOnce() throws {
        var e = engineWitnessing()
        #expect(e.update(
            input([session("S1", status: .waiting(.inputNeeded), statusAt: at(0))]),
            now: at(0)).isEmpty)                      // 還在合併視窗裡，先不發
        let events = e.flush(now: at(4))
        #expect(events.count == 1)
        guard case .waiting(let alert) = try #require(events.first) else {
            Issue.record("不是 waiting 事件"); return
        }
        #expect(alert.sessions.count == 1)
        #expect(alert.sessions[0].sessionId == "S1")
        #expect(alert.sessions[0].waitingFor == .inputNeeded)
        #expect(alert.sessions[0].project == "usage")
        #expect(alert.isRepeat == false)
        #expect(alert.coalesced == false)
    }

    @Test("恰好在 T+300 再推一次，之後永遠安靜")
    func exactlyOneRepeatAtFiveMinutes() {
        var e = engineWitnessing()
        let s = session("S1", status: .waiting(.inputNeeded), statusAt: at(0))
        _ = e.update(input([s]), now: at(0))
        #expect(e.flush(now: at(4)).count == 1)

        // 299 秒還不到
        _ = e.update(input([s]), now: at(299))
        #expect(e.flush(now: at(299)).isEmpty)

        // 300 秒整，恰好一次
        _ = e.update(input([s]), now: at(300))
        let repeated = e.flush(now: at(300))
        #expect(repeated.count == 1)
        if case .waiting(let a) = repeated[0] { #expect(a.isRepeat == true) }

        // 之後再也不發
        for t in stride(from: 303.0, to: 1800.0, by: 3.0) {
            _ = e.update(input([s]), now: at(t))
            #expect(e.flush(now: at(t)).isEmpty)
        }
    }

    @Test("重推的那一次不受 60 秒去重窗影響 —— 它就是同一個鍵，刻意要再講一次")
    func theRepeatIsNotSwallowedByDedup() {
        var e = engineWitnessing()
        let s = session("S1", status: .waiting(.inputNeeded), statusAt: at(0))
        _ = e.update(input([s]), now: at(0))
        #expect(e.flush(now: at(4)).count == 1)
        _ = e.update(input([s]), now: at(300))
        #expect(e.flush(now: at(300)).count == 1)
    }

    // ── statusUpdatedAt：最常見的那一種等待 ──────────────────────

    @Test("回答完又馬上要批准 —— 中間那段 busy 整拍錯過，仍然算新事件")
    func newEpisodeDetectedByStatusUpdatedAt() {
        var e = engineWitnessing()
        _ = e.update(input([session("S1", status: .waiting(.inputNeeded), statusAt: at(0))]),
                     now: at(0))
        #expect(e.flush(now: at(4)).count == 1)

        // 下一拍：還是 waiting，但 statusUpdatedAt 變了 —— 中間的 busy 沒被看到。
        // 這是實際使用上最常見的一種等待，靠「看到離開 waiting」會整個漏掉。
        _ = e.update(input([session("S1", status: .waiting(.permissionPrompt), statusAt: at(90))]),
                     now: at(90))
        #expect(e.flush(now: at(94)).count == 1)
    }

    @Test("statusUpdatedAt 沒變就不是新事件，即使 waitingFor 被改寫")
    func sameStatusUpdatedAtIsTheSameEpisode() {
        var e = engineWitnessing()
        _ = e.update(input([session("S1", status: .waiting(.inputNeeded), statusAt: at(0))]),
                     now: at(0))
        #expect(e.flush(now: at(4)).count == 1)
        _ = e.update(input([session("S1", status: .waiting(.permissionPrompt), statusAt: at(0))]),
                     now: at(20))
        #expect(e.flush(now: at(24)).isEmpty)
    }

    @Test("舊版本沒有 statusUpdatedAt —— 退回轉換判定，不 crash 也不狂發")
    func oldVersionWithoutStatusUpdatedAtFallsBackToTransition() {
        var e = NotificationEngine()
        _ = e.update(input([session("S1", status: .busy, statusAt: nil)]), now: at(-10))
        _ = e.update(input([session("S1", status: .waiting(.inputNeeded), statusAt: nil)]),
                     now: at(0))
        #expect(e.flush(now: at(4)).count == 1)
        for t in stride(from: 8.0, to: 200.0, by: 3.0) {
            _ = e.update(input([session("S1", status: .waiting(.inputNeeded), statusAt: nil)]),
                         now: at(t))
            #expect(e.flush(now: at(t)).isEmpty)
        }
    }

    // ── 解除 ───────────────────────────────────────────────────

    @Test("啟動時就在等的那個，五分鐘後也不可以突然冒出來")
    func startupSuppressedWaitNeverFiresItsRepeat() {
        // 第一次觀測不發，但排程重推如果照常安排，T+300 就會冒出一則 ——
        // 那等於「不發」只延後了五分鐘，而且冒出來的還是被當成重推的那一種。
        var e = NotificationEngine()
        let s = session("S1", status: .waiting(.inputNeeded), statusAt: at(0))
        _ = e.update(input([s]), now: at(0))
        for t in stride(from: 3.0, to: 900.0, by: 3.0) {
            _ = e.update(input([s]), now: at(t))
            #expect(e.flush(now: at(t)).isEmpty)
        }
    }

    @Test("已經回答完的等待，不可以在合併視窗結束後才冒出來")
    func answeredDuringTheCoalesceWindowIsDropped() {
        // 合併視窗是 4 秒，輪詢是 3 秒 —— 在視窗裡回答完是很正常的事。
        // 不重新確認的話，浮窗會對著一個你剛剛才回答過的問題喊。
        var e = engineWitnessing()
        _ = e.update(input([session("S1", status: .waiting(.inputNeeded), statusAt: at(0))]),
                     now: at(0))
        _ = e.update(input([session("S1", status: .busy, statusAt: at(3))]), now: at(3))
        #expect(e.flush(now: at(4)).isEmpty)
    }

    @Test("statusUpdatedAt 是垃圾也不可以 crash —— 那是磁碟上的數字")
    func absurdStatusUpdatedAtDoesNotTrap() {
        var e = engineWitnessing()
        let absurd = Date(timeIntervalSince1970: 1e18)
        _ = e.update(input([session("S1", status: .waiting(.inputNeeded), statusAt: absurd)]),
                     now: at(0))
        _ = e.flush(now: at(4))     // 只要跑得完就算過 —— Int(Double) 會 trap
    }

    @Test("離開等待就整組重置，下一次拿回完整預算")
    func leavingWaitingResetsTheBudget() {
        var e = engineWitnessing()
        _ = e.update(input([session("S1", status: .waiting(.inputNeeded), statusAt: at(0))]),
                     now: at(0))
        #expect(e.flush(now: at(4)).count == 1)

        _ = e.update(input([session("S1", status: .busy, statusAt: at(10))]), now: at(10))
        _ = e.update(input([session("S1", status: .waiting(.inputNeeded), statusAt: at(20))]),
                     now: at(20))
        #expect(e.flush(now: at(24)).count == 1)
    }

    @Test("漏看一拍不可以讓同一個等待重講一次，也不可以把重推的額度發回去")
    func oneMissedObservationDoesNotRestartTheEpisode() {
        // 存活閘打嗝、contentsOfDirectory 失敗，都會讓一個還在等的 session
        // 從某一拍的讀取結果裡整個消失。當場清掉狀態的話，它回來時
        // statusUpdatedAt 一模一樣，卻會被當成新事件 —— 同一個問題再喊一次、
        // 而且「恰好一次」的重推額度也跟著發回去。
        var e = engineWitnessing()
        let s = session("S1", status: .waiting(.inputNeeded), statusAt: at(0))
        _ = e.update(input([s]), now: at(0))
        #expect(e.flush(now: at(4)).count == 1)
        _ = e.update(input([s]), now: at(300))
        #expect(e.flush(now: at(300)).count == 1)      // 那一次重推

        _ = e.update(input([]), now: at(600))          // 漏看一拍
        _ = e.update(input([s]), now: at(603))         // 回來了，同一個 episode
        #expect(e.flush(now: at(607)).isEmpty)

        // 之後也不可以再冒出第二次重推
        for t in stride(from: 610.0, to: 1500.0, by: 3.0) {
            _ = e.update(input([s]), now: at(t))
            #expect(e.flush(now: at(t)).isEmpty)
        }
    }

    @Test("真的結束了（連續消失夠久）才可以重置")
    func aLongAbsenceDoesResetTheEpisode() {
        var e = engineWitnessing()
        let s = session("S1", status: .waiting(.inputNeeded), statusAt: at(0))
        _ = e.update(input([s]), now: at(0))
        #expect(e.flush(now: at(4)).count == 1)

        // 連續兩次以上觀測不到，而且超過 30 秒 —— 這次是真的沒了。
        for t in stride(from: 10.0, through: 70.0, by: 3.0) {
            _ = e.update(input([]), now: at(t))
        }
        // 同一個 episode 回來，但狀態已經過期，所以它是一次新的等待。
        _ = e.update(input([s]), now: at(80))
        #expect(e.flush(now: at(84)).count == 1)
    }

    @Test("session 整個消失（關掉終端機）不算解除也不會發通知")
    func vanishedSessionIsSilent() {
        var e = engineWitnessing()
        _ = e.update(input([session("S1", status: .waiting(.inputNeeded), statusAt: at(0))]),
                     now: at(0))
        #expect(e.flush(now: at(4)).count == 1)
        #expect(e.update(input([]), now: at(10)).isEmpty)
        #expect(e.flush(now: at(14)).isEmpty)
    }

    @Test("等待中的 session 帶著它的名字與 pid —— 跳過去要靠 pid 找擁有它的 app")
    func alertCarriesWhatTheJumpButtonNeeds() throws {
        var e = engineWitnessing()
        _ = e.update(input([session("S1", status: .waiting(.permissionPrompt),
                                    statusAt: at(0), pid: 4242)]), now: at(0))
        let events = e.flush(now: at(4))
        guard case .waiting(let a) = try #require(events.first) else {
            Issue.record("不是 waiting 事件"); return
        }
        #expect(a.sessions[0].pid == 4242)
        #expect(a.sessions[0].name == "usage-c9")
        #expect(a.sessions[0].since == at(0))
    }
}

// ═══════════════════════════════════════════════════════════════
//  去重與合併
// ═══════════════════════════════════════════════════════════════

/// 設計文件裡最重要的一條規則：**subagent 個別完成絕不通知**。
/// 天真的做法會在十隻 agent 收工時產生十則橫幅 —— 那是攻擊，不是通知。
/// 同一條規則套在 T1 上，就是這裡的合併視窗。
@Suite("NotificationEngine — 去重與合併")
struct NotificationDedupTests {

    let t0 = Date(timeIntervalSince1970: 1_789_660_000)
    func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    func session(_ id: String, _ status: SessionStatus, _ statusAt: Date?,
                 cwd: String = "/Users/x/p/usage") -> LiveSession {
        LiveSession(session: ClaudeSession(
            pid: 1000 + Int32(id.hashValue % 100), sessionId: id, cwd: cwd,
            startedAt: t0.addingTimeInterval(-3600), status: status,
            statusUpdatedAt: statusAt))
    }

    func input(_ s: [LiveSession], presence: Presence = .atKeyboard) -> NotificationInput {
        NotificationInput(sessions: s, trees: [:], usage: nil, presence: presence)
    }

    func witnessing(_ ids: [String]) -> NotificationEngine {
        var e = NotificationEngine()
        _ = e.update(input(ids.map { session($0, .busy, at(-10)) }), now: at(-10))
        return e
    }

    @Test("三個一起卡住只發一則摘要 —— 不是三個視窗")
    func threeAtOnceCoalesceIntoOne() throws {
        var e = witnessing(["A", "B", "C"])
        _ = e.update(input([
            session("A", .waiting(.inputNeeded), at(0), cwd: "/p/usage"),
            session("B", .waiting(.permissionPrompt), at(0), cwd: "/p/F1"),
            session("C", .waiting(.inputNeeded), at(0), cwd: "/p/PEO"),
        ]), now: at(0))
        let events = e.flush(now: at(4))
        #expect(events.count == 1)
        guard case .waiting(let a) = try #require(events.first) else {
            Issue.record("不是 waiting 事件"); return
        }
        #expect(a.coalesced == true)
        #expect(a.sessions.count == 3)
    }

    @Test("兩個不合併 —— 門檻是三個，兩個各自完整比一則摘要有用")
    func twoStaySeparate() {
        var e = witnessing(["A", "B"])
        _ = e.update(input([
            session("A", .waiting(.inputNeeded), at(0)),
            session("B", .waiting(.permissionPrompt), at(0)),
        ]), now: at(0))
        let events = e.flush(now: at(4))
        #expect(events.count == 2)
        for case .waiting(let a) in events { #expect(a.coalesced == false) }
    }

    @Test("隔一拍才卡住的第三個仍然併得進來 —— 合併視窗是 4 秒不是一拍")
    func lateThirdStillCoalesces() throws {
        var e = witnessing(["A", "B", "C"])
        _ = e.update(input([
            session("A", .waiting(.inputNeeded), at(0)),
            session("B", .waiting(.inputNeeded), at(0)),
        ]), now: at(0))
        _ = e.update(input([
            session("A", .waiting(.inputNeeded), at(0)),
            session("B", .waiting(.inputNeeded), at(0)),
            session("C", .waiting(.inputNeeded), at(3)),
        ]), now: at(3))
        let events = e.flush(now: at(4))
        #expect(events.count == 1)
        guard case .waiting(let a) = try #require(events.first) else {
            Issue.record("不是 waiting 事件"); return
        }
        #expect(a.coalesced == true)
        #expect(a.sessions.count == 3)
    }

    @Test("合併後最久的那個排最前面 —— 先處理擋最久的")
    func oldestFirstInACoalescedAlert() throws {
        var e = witnessing(["A", "B", "C"])
        _ = e.update(input([
            session("A", .waiting(.inputNeeded), at(-100)),
            session("B", .waiting(.inputNeeded), at(-500)),
            session("C", .waiting(.inputNeeded), at(-20)),
        ]), now: at(0))
        let events = e.flush(now: at(4))
        guard case .waiting(let a) = try #require(events.first) else {
            Issue.record("不是 waiting 事件"); return
        }
        #expect(a.sessions.map(\.sessionId) == ["B", "A", "C"])
    }

    @Test("相同去重鍵 60 秒內抑制")
    func sameKeySuppressedWithinSixtySeconds() {
        // 直接餵同一個鍵三次，把去重窗單獨挑出來測 —— 走真實路徑的話，
        // 「不會重發」有好幾條規則同時擋著，測到的就不是去重窗本身。
        var e = NotificationEngine()
        e.forceEnqueueForTesting(sessionId: "A", now: at(0))
        #expect(e.flush(now: at(4)).count == 1)

        e.forceEnqueueForTesting(sessionId: "A", now: at(30))
        #expect(e.flush(now: at(34)).isEmpty)

        // 超過 60 秒之後同鍵可以再發
        e.forceEnqueueForTesting(sessionId: "A", now: at(70))
        #expect(e.flush(now: at(74)).count == 1)
    }

    @Test("去重表不會無限長大 —— 每個等待事件都會留下一個新鍵")
    func dedupTableIsBounded() {
        // episode 鍵是 statusUpdatedAt 的毫秒數，所以每一次等待都是一個**新**鍵。
        // 不清的話，一台開著幾週的機器會累積幾萬筆再也不會被查到的條目。
        var e = NotificationEngine()
        for i in 0..<500 {
            e.forceEnqueueForTesting(sessionId: "S\(i)", now: at(Double(i) * 10))
            _ = e.flush(now: at(Double(i) * 10 + 5))
        }
        // 去重窗是 60 秒，所以只有最近 60 秒內發過的鍵還有意義。
        #expect(e.trackedDedupKeys <= 16)
    }

    @Test("延後的警示只留還在等的那些")
    func aDeferredAlertKeepsOnlyTheSessionsStillWaiting() throws {
        // 使用者離開螢幕時警示會被留著，等人回來再補上。等的期間他可能
        // 從別的地方回答了其中一個 —— 那一個就不可以再出現在補上的那扇窗裡。
        let a = WaitingSession(sessionId: "A", pid: 1, project: "usage", name: nil,
                               waitingFor: .inputNeeded, since: at(0), cwd: "/p/usage",
                               episode: "e1")
        let b = WaitingSession(sessionId: "B", pid: 2, project: "F1", name: nil,
                               waitingFor: .inputNeeded, since: at(10), cwd: "/p/F1",
                               episode: "e2")
        let alert = WaitingAlert(primary: a, others: [b], coalesced: false, isRepeat: false)

        let kept = try #require(alert.retaining(["B"]))
        #expect(kept.primary.sessionId == "B")
        #expect(kept.others.isEmpty)
    }

    @Test("全部都回答完了就整個丟掉 —— 不要補一扇空窗")
    func aFullyAnsweredDeferredAlertDisappears() {
        let a = WaitingSession(sessionId: "A", pid: 1, project: "usage", name: nil,
                               waitingFor: .inputNeeded, since: at(0), cwd: "/p/usage",
                               episode: "e1")
        #expect(WaitingAlert(primary: a, coalesced: false, isRepeat: false)
                    .retaining([]) == nil)
    }

    @Test("補上的那一扇不是「重推」—— 你根本還沒看過第一次")
    func theDeferredAlertIsNotARepeat() throws {
        // isRepeat 會讓 presenter 不出聲（第二次同樣的聲音只會教會耳朵忽略它）。
        // 但延後補上的這一扇是使用者**第一次**看到它，所以該出聲。
        let a = WaitingSession(sessionId: "A", pid: 1, project: "usage", name: nil,
                               waitingFor: .inputNeeded, since: at(0), cwd: "/p/usage",
                               episode: "e1")
        let repeated = WaitingAlert(primary: a, coalesced: false, isRepeat: true)
        #expect(try #require(repeated.retaining(["A"])).isRepeat == false)
    }

    @Test("留下來的仍然照等待時間排序，而且合併旗標跟著新的數量走")
    func retainingRecomputesTheCoalescedFlag() throws {
        let s = (0..<4).map { i in
            WaitingSession(sessionId: "S\(i)", pid: Int32(i), project: "p\(i)", name: nil,
                           waitingFor: .inputNeeded, since: at(Double(i) * -100),
                           cwd: "/p", episode: "e\(i)")
        }
        let alert = WaitingAlert(primary: s[3], others: [s[2], s[1], s[0]],
                                 coalesced: true, isRepeat: false)
        let kept = try #require(alert.retaining(["S0", "S1"]))
        #expect(kept.sessions.count == 2)
        #expect(kept.coalesced == false)          // 剩兩個就不再是合併
        #expect(kept.primary.sessionId == "S1")   // 等比較久的那個
    }

    @Test("去重鍵是穩定字串，不是 hashValue —— Hasher 每個行程重新設種子")
    func dedupKeyIsAStableString() {
        let k = NotificationEngine.waitingDedupKey(sessionId: "S1", episode: "1789660000000")
        #expect(k == "S1|waiting|1789660000000")
    }
}

// ═══════════════════════════════════════════════════════════════
//  T2：扇出整批排空
// ═══════════════════════════════════════════════════════════════

/// 「排空」只能用**正面證據**定義。
///
/// `AgentTreeBuilder` 把每一隻一般 Agent subagent 都寫成 `.unknown`，而
/// `WorkflowJournalReader` 讀不到 journal 時整組也是 `.unknown`。
/// 用「沒有人在跑」當條件，等於把「讀不到」當成「跑完了」——
/// 那會在 workflow 剛建好目錄、journal 還沒寫出來的那一拍發一則「全部完成」。
@Suite("NotificationEngine — T2 扇出整批排空")
struct NotificationT2Tests {

    let t0 = Date(timeIntervalSince1970: 1_789_660_000)
    func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    func node(_ id: String, _ state: AgentRunState) -> AgentNode {
        AgentNode(meta: AgentMeta(agentId: id, agentType: "workflow-subagent",
                                  description: "recon", spawnDepth: 1,
                                  workflowPhase: "Research"),
                  runState: state)
    }

    func tree(_ states: [AgentRunState], runStatus: String? = nil,
              workflowId: String = "wf_1",
              runDuration: TimeInterval? = nil) -> [String: AgentTree] {
        let agents = states.enumerated().map { node("a\($0.offset)", $0.element) }
        return ["S1": AgentTree(
            sessionId: "S1", agents: [],
            workflows: [WorkflowGroup(workflowId: workflowId, latestPhase: "Research",
                                      agents: agents, runStatus: runStatus,
                                      runDuration: runDuration)])]
    }

    func input(_ trees: [String: AgentTree], presence: Presence = .atKeyboard)
    -> NotificationInput {
        NotificationInput(sessions: [], trees: trees, usage: nil, presence: presence)
    }

    @Test("看過還沒跑完，再看到全部完成 —— 發一則，只有一則")
    func drainedAfterBeingSeenIncomplete() throws {
        var e = NotificationEngine()
        _ = e.update(input(tree([.running, .running, .finished])), now: at(0))
        _ = e.update(input(tree([.finished, .finished, .finished],
                                runStatus: "completed")), now: at(30))
        let events = e.flush(now: at(34))
        #expect(events.count == 1)
        guard case .batchDrained(let b) = try #require(events.first) else {
            Issue.record("不是 batchDrained 事件"); return
        }
        #expect(b.workflowId == "wf_1")
        #expect(b.total == 3)
        #expect(b.latestPhase == "Research")
        #expect(b.outcome == .completed)

        // 之後不再發
        _ = e.update(input(tree([.finished, .finished, .finished],
                                runStatus: "completed")), now: at(60))
        #expect(e.flush(now: at(64)).isEmpty)
    }

    @Test("階段交界不算排空 —— journal 說全部完成，但 run 狀態檔還不存在")
    func stageBoundaryIsNotDrained() {
        // 多階段 pipeline 的第一個階段全部收尾、下一個階段還沒 spawn 的那一拍：
        // meta 檔還不存在，所以 total 就是「到目前為止 spawn 過幾隻」，
        // finishedCount == total 當場成立。磁碟上 32 個 workflow 有 25 個
        // 真的出現過這個窗口，8 個 ≥3 秒也就是必定被 3 秒輪詢取樣到。
        var e = NotificationEngine()
        _ = e.update(input(tree([.running, .running])), now: at(0))
        _ = e.update(input(tree([.finished, .finished])), now: at(3))
        #expect(e.flush(now: at(7)).isEmpty)
    }

    @Test("階段交界之後真正跑完仍然要發 —— notified 不可以是單向閂鎖")
    func realDrainFiresAfterAStageBoundary() throws {
        // 這一則釘的是上一則修壞掉的那個方向：光是「階段交界不發」還不夠，
        // 因為 notified 一旦被誤報閂住就永遠不會放開，於是真正跑完的那一刻
        // 反而全靜音 —— 剛好跟這個功能的目的相反。
        var e = NotificationEngine()
        _ = e.update(input(tree([.running, .running])), now: at(0))
        _ = e.update(input(tree([.finished, .finished])), now: at(3))          // 階段交界
        _ = e.flush(now: at(7))
        _ = e.update(input(tree([.finished, .finished, .running, .running])),
                     now: at(10))                                              // 下一階段開跑
        _ = e.update(input(tree([.finished, .finished, .finished, .finished],
                                runStatus: "completed")), now: at(40))
        let events = e.flush(now: at(44))
        #expect(events.count == 1)
        guard case .batchDrained(let b) = try #require(events.first) else {
            Issue.record("不是 batchDrained 事件"); return
        }
        #expect(b.total == 4)
    }

    @Test("啟動前就跑完的那批不發 —— 沒看過它還沒完成的樣子")
    func alreadyDrainedAtLaunchIsSilent() {
        // ⚠️ 兩拍都要帶終結狀態。不帶的話這一則會因為「沒有 run 終結證據」而通過，
        // 而那是**另一道閘**在擋 —— 它就不再測得到 everObservedIncomplete 了。
        var e = NotificationEngine()
        _ = e.update(input(tree([.finished, .finished], runStatus: "completed")), now: at(0))
        #expect(e.flush(now: at(4)).isEmpty)
        _ = e.update(input(tree([.finished, .finished], runStatus: "completed")), now: at(30))
        #expect(e.flush(now: at(34)).isEmpty)
    }

    @Test("journal 讀不到讓整組變 unknown —— 不可以當成排空")
    func unknownIsNotDrained() {
        var e = NotificationEngine()
        _ = e.update(input(tree([.running, .running])), now: at(0))
        _ = e.update(input(tree([.unknown, .unknown])), now: at(30))
        #expect(e.flush(now: at(34)).isEmpty)
    }

    @Test("剛建好目錄、journal 還沒寫 —— 一出生就全 unknown，不可以發")
    func bornUnknownIsNotDrained() {
        var e = NotificationEngine()
        _ = e.update(input(tree([.unknown, .unknown, .unknown])), now: at(0))
        _ = e.update(input(tree([.unknown, .unknown, .unknown])), now: at(30))
        #expect(e.flush(now: at(34)).isEmpty)
    }

    @Test("整組憑空消失一拍不等於排空 —— 不存在不是資訊")
    func vanishingIsNotDraining() {
        var e = NotificationEngine()
        _ = e.update(input(tree([.running, .finished])), now: at(0))
        _ = e.update(input([:]), now: at(3))              // 讀檔失敗，整組消失
        #expect(e.flush(now: at(7)).isEmpty)
        _ = e.update(input(tree([.running, .finished])), now: at(6))   // 又回來了
        #expect(e.flush(now: at(10)).isEmpty)
    }

    @Test("進度倒退不可以讓已經排空的又變回沒排空")
    func peakFinishedIsMonotonic() {
        var e = NotificationEngine()
        _ = e.update(input(tree([.running, .running])), now: at(0))
        _ = e.update(input(tree([.finished, .running])), now: at(3))
        _ = e.update(input(tree([.unknown, .running])), now: at(6))    // journal 暫時讀不到
        _ = e.update(input(tree([.finished, .finished], runStatus: "completed")), now: at(9))
        #expect(e.flush(now: at(13)).count == 1)
    }

    @Test("agent 清單縮水不可以讓還在跑的那批看起來排空了")
    func shrinkingGroupIsNotDrained() {
        // meta 檔沒通過新鮮度閘、或目錄讀一半，group 會少掉幾隻。
        // 只看當下的 total 的話，「5 隻裡完成 2 隻」會在縮到 2 隻時
        // 變成「2/2 全部完成」。記得看過的最大值才擋得住。
        var e = NotificationEngine()
        // 帶終結狀態，這一則才測得到 total 取 max 那一條：run 真的結束了，
        // 但新鮮度閘藏掉三隻，於是當下的 group 只剩 2 隻。
        _ = e.update(input(tree([.running, .running, .running, .finished, .finished])), now: at(0))
        _ = e.update(input(tree([.finished, .finished], runStatus: "completed")), now: at(30))
        #expect(e.flush(now: at(34)).isEmpty)
    }

    @Test("被你停掉的 run 完全不發 —— 是你自己按的，你知道")
    func killedRunIsSilent() {
        var e = NotificationEngine()
        _ = e.update(input(tree([.running, .running])), now: at(0))
        // ⚠️ 刻意帶一個**合法的** runDuration：killed 帶著一個看起來很正常的
        // 時長卻仍然完全不發，是這次改動最容易被誤傷的一格 ——
        // 一個把「有 duration」當成「有終結證據」的實作會讓 killed 開始出聲。
        _ = e.update(input(tree([.finished, .finished], runStatus: "killed",
                                runDuration: 345.16)), now: at(30))
        #expect(e.flush(now: at(34)).isEmpty)
    }

    @Test("失敗的 run 會發，但措辭是失敗不是完成")
    func failedRunSaysFailed() throws {
        var e = NotificationEngine()
        _ = e.update(input(tree([.running, .running])), now: at(0))
        _ = e.update(input(tree([.finished, .finished], runStatus: "failed")), now: at(30))
        let events = e.flush(now: at(34))
        guard case .batchDrained(let b) = try #require(events.first) else {
            Issue.record("不是 batchDrained 事件"); return
        }
        #expect(b.outcome == .failed)
    }

    @Test("一般 Agent 扇出永遠不會發 T2 —— 它的狀態是 unknown，沒有正面證據")
    func plainAgentFanOutNeverFires() {
        var e = NotificationEngine()
        let plain = ["S1": AgentTree(
            sessionId: "S1",
            agents: [node("p1", .unknown), node("p2", .unknown)],
            workflows: [])]
        _ = e.update(input(plain), now: at(0))
        _ = e.update(input(plain), now: at(30))
        #expect(e.flush(now: at(34)).isEmpty)
    }

    @Test("兩個 workflow 各發各的 —— 絕不聚合成一則")
    func perWorkflowNeverAggregated() {
        var e = NotificationEngine()
        func two(_ a: [AgentRunState], _ b: [AgentRunState],
                 aStatus: String? = nil, bStatus: String? = nil) -> [String: AgentTree] {
            ["S1": AgentTree(sessionId: "S1", agents: [], workflows: [
                WorkflowGroup(workflowId: "wf_1", latestPhase: "A",
                              agents: a.enumerated().map { node("a\($0.offset)", $0.element) },
                              runStatus: aStatus),
                WorkflowGroup(workflowId: "wf_2", latestPhase: "B",
                              agents: b.enumerated().map { node("b\($0.offset)", $0.element) },
                              runStatus: bStatus),
            ])]
        }
        _ = e.update(input(two([.running], [.running])), now: at(0))
        _ = e.update(input(two([.finished], [.running], aStatus: "completed")), now: at(30))
        #expect(e.flush(now: at(34)).count == 1)
        _ = e.update(input(two([.finished], [.finished],
                               aStatus: "completed", bStatus: "completed")), now: at(60))
        #expect(e.flush(now: at(64)).count == 1)
    }

    @Test("app 重啟後接手跑到一半的 workflow —— duration 說的是 run 跑了多久，不是 app 看了多久")
    func durationIsTheRunsNotTheObservers() throws {
        // 第一次觀測就已經是 [.running, .running]（**不含出生那一拍**），
        // 這正是 make_app.sh 重裝之後接手的形狀。
        // 724 = 12m 04s，而 app 只看了 40 秒 —— 舊實作回 40。
        var e = NotificationEngine()
        _ = e.update(input(tree([.running, .running])), now: at(0))
        _ = e.update(input(tree([.finished, .finished], runStatus: "completed",
                                runDuration: 724)), now: at(40))
        let events = e.flush(now: at(44))
        guard case .batchDrained(let b) = try #require(events.first) else {
            Issue.record("不是 batchDrained 事件"); return
        }
        #expect(b.runDuration == 724)
    }

    @Test("app 看得比 run 還久 —— duration 仍然是 run 自己說的那個")
    func durationIsNotClampedByObservation() throws {
        // 上一則抓「app 看得比 run 短」，這一則抓「看得比 run 長」。
        // 只有上一則的話，一個寫成 `min(now − firstSeen, runDuration)` 的實作
        // 會矇混過去；兩則一起就矇不過。
        var e = NotificationEngine()
        _ = e.update(input(tree([.running, .running])), now: at(0))
        _ = e.update(input(tree([.finished, .finished], runStatus: "completed",
                                runDuration: 60)), now: at(600))
        let events = e.flush(now: at(604))
        guard case .batchDrained(let b) = try #require(events.first) else {
            Issue.record("不是 batchDrained 事件"); return
        }
        #expect(b.runDuration == 60)
    }

    @Test("run 狀態檔有 status 卻沒有 durationMs —— T2 照發，只是那一格是 nil")
    func missingDurationDoesNotSwallowTheEvent() throws {
        // 釘的是兩層的分界：status 是排空的正面證據，duration 只是附屬資訊。
        // 「缺 duration 就不發」的實作會讓事件數變 0 → 紅。
        var e = NotificationEngine()
        _ = e.update(input(tree([.running, .running])), now: at(0))
        _ = e.update(input(tree([.finished, .finished], runStatus: "completed",
                                runDuration: nil)), now: at(30))
        let events = e.flush(now: at(34))
        #expect(events.count == 1)
        guard case .batchDrained(let b) = try #require(events.first) else {
            Issue.record("不是 batchDrained 事件"); return
        }
        #expect(b.runDuration == nil)
    }

    @Test("journal 讀不到時 T2 照發，只是階段是 nil —— Core 不塞預設字串")
    func drainedWithoutAPhaseStillFires() throws {
        // ⚠️ 這一則今天就是綠的，它是**守門員**不是修正 —— 但它守的是一條
        // 真的走得到的路：run 狀態檔終結了、journal 卻讀不到（整組變 unknown
        // 之外，`terminated` 會把每一隻折成 .finished），於是 T2 帶著 nil 階段發出去。
        // Stage 8 要把這個字串端上面板之前得先知道它可以是 nil。
        var e = NotificationEngine()
        func g(_ states: [AgentRunState], _ runStatus: String?) -> [String: AgentTree] {
            ["S1": AgentTree(sessionId: "S1", agents: [], workflows: [
                WorkflowGroup(workflowId: "wf_1", latestPhase: nil,
                              agents: states.enumerated().map { node("a\($0.offset)", $0.element) },
                              runStatus: runStatus)])]
        }
        _ = e.update(input(g([.running, .running], nil)), now: at(0))
        _ = e.update(input(g([.finished, .finished], "completed")), now: at(30))
        let events = e.flush(now: at(34))
        #expect(events.count == 1)
        guard case .batchDrained(let b) = try #require(events.first) else {
            Issue.record("不是 batchDrained 事件"); return
        }
        #expect(b.latestPhase == nil)
    }

    @Test("空的 group 不算排空 —— total 是 0 的時候什麼都沒發生")
    func emptyGroupIsNotDrained() {
        var e = NotificationEngine()
        let empty = ["S1": AgentTree(sessionId: "S1", agents: [],
                                     workflows: [WorkflowGroup(workflowId: "wf_1",
                                                               latestPhase: nil,
                                                               agents: [])])]
        _ = e.update(input(empty), now: at(0))
        _ = e.update(input(empty), now: at(30))
        #expect(e.flush(now: at(34)).isEmpty)
    }
}

// ═══════════════════════════════════════════════════════════════
//  T2：該不該出聲
// ═══════════════════════════════════════════════════════════════

/// 事件發不發是上面那個 suite 的事；**這裡只管音量**。
///
/// 分成兩個 suite 是刻意的：一個變紅的測試要能立刻告訴你是哪一道閘壞了。
@Suite("NotificationEngine — T2 該不該出聲")
struct NotificationT2AudibilityTests {

    let t0 = Date(timeIntervalSince1970: 1_789_660_000)
    func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    func node(_ id: String, _ state: AgentRunState) -> AgentNode {
        AgentNode(meta: AgentMeta(agentId: id, agentType: "workflow-subagent",
                                  description: "recon", spawnDepth: 1,
                                  workflowPhase: "Research"),
                  runState: state)
    }

    func tree(_ states: [AgentRunState], runStatus: String? = nil,
              workflowId: String = "wf_1") -> [String: AgentTree] {
        let agents = states.enumerated().map { node("a\($0.offset)", $0.element) }
        return ["S1": AgentTree(
            sessionId: "S1", agents: [],
            workflows: [WorkflowGroup(workflowId: workflowId, latestPhase: "Research",
                                      agents: agents, runStatus: runStatus)])]
    }

    /// ⚠️ 這個 suite 的 `presence` **刻意必填**：這裡每一則測試都是在講在場，
    /// 一個預設值會讓「忘了設」看起來像「故意設成這樣」。
    func input(_ trees: [String: AgentTree], presence: Presence) -> NotificationInput {
        NotificationInput(sessions: [], trees: trees, usage: nil, presence: presence)
    }

    /// 讓一個 workflow 從「還在跑」走到「run 終結」，回傳 flush 出來的事件。
    @discardableResult
    func drain(_ e: inout NotificationEngine, presence: Presence,
               workflowId: String = "wf_1", runStatus: String = "completed",
               startingAt s0: TimeInterval = 0) -> [NotificationEvent] {
        _ = e.update(input(tree([.running, .running], workflowId: workflowId),
                           presence: presence), now: at(s0))
        _ = e.update(input(tree([.finished, .finished], runStatus: runStatus,
                                workflowId: workflowId),
                           presence: presence), now: at(s0 + 3))
        return e.flush(now: at(s0 + 7))
    }

    func audibility(_ events: [NotificationEvent]) -> Audibility? {
        guard let first = events.first, case .batchDrained(let b) = first else { return nil }
        return b.audibility
    }

    @Test("人在鍵盤前、一批排空 —— 事件發出來而且會出聲")
    func audibleAtTheKeyboard() {
        var e = NotificationEngine()
        let events = drain(&e, presence: .atKeyboard)
        #expect(events.count == 1)
        #expect(audibility(events) == .audible)
    }

    @Test("鎖定＋螢幕睡＋閒置 866 秒 —— 事件照發，只是不出聲")
    func theMeasuredEmptyChairIsSilent() {
        // 這就是 2026-09-19 02:28:23 實測抓到的那一格。
        // ⚠️ 同時斷言 `count == 1`：**閘管的是音量，不是事件的存在**。
        // 把整則吞掉的實作會讓選單列那一下瞬時訊號也消失，
        // 而那一下是免費的 —— 人不在的時候它什麼都沒花。
        var e = NotificationEngine()
        let events = drain(&e, presence: .away)
        #expect(events.count == 1)
        #expect(audibility(events) == .silent(.noOneWatching))
    }

    @Test("螢幕鎖著但閒置 0 秒 —— 仍然不出聲。三個訊號是 OR")
    func lockedWithZeroIdleIsStillSilent() {
        var e = NotificationEngine()
        let locked = Presence(screenLocked: true, screensAsleep: false, idleSeconds: 0)
        #expect(audibility(drain(&e, presence: locked)) == .silent(.noOneWatching))
    }

    @Test("螢幕睡著但閒置 0 秒 —— 仍然不出聲")
    func sleepingScreenWithZeroIdleIsStillSilent() {
        var e = NotificationEngine()
        let asleep = Presence(screenLocked: false, screensAsleep: true, idleSeconds: 0)
        #expect(audibility(drain(&e, presence: asleep)) == .silent(.noOneWatching))
    }

    @Test("閒置讀不到（nil）不出聲 —— 出聲要有正面證據")
    func unreadableIdleIsSilent() {
        // 直接照抄 `ScreenPresence` 那個 `?? 0` 的實作會在這裡紅 ——
        // 那種版本會對著一台量不到 HID 的機器播音效。
        var e = NotificationEngine()
        let unknown = Presence(screenLocked: false, screensAsleep: false, idleSeconds: nil)
        #expect(audibility(drain(&e, presence: unknown)) == .silent(.noOneWatching))
    }

    @Test("失敗的那批即使人在也不出聲 —— 而且理由要說得出是哪一個")
    func failedIsSilentWithItsOwnReason() {
        var e = NotificationEngine()
        let events = drain(&e, presence: .atKeyboard, runStatus: "failed")
        #expect(events.count == 1)
        #expect(audibility(events) == .silent(.failedOutcome))
    }

    @Test("在場取的是 flush 那一拍 —— 入列時人不在、四秒合併窗內回到座位就要出聲")
    func presenceIsSampledAtFlush() {
        // 抓「把 presence 存進 BatchState、在入列那一刻就決定」的實作。
        var e = NotificationEngine()
        _ = e.update(input(tree([.running, .running]), presence: .away), now: at(0))
        _ = e.update(input(tree([.finished, .finished], runStatus: "completed"),
                           presence: .away), now: at(3))
        _ = e.update(input(tree([.finished, .finished], runStatus: "completed"),
                           presence: .atKeyboard), now: at(6))
        #expect(audibility(e.flush(now: at(7))) == .audible)
    }

    @Test("在場取的是 flush 那一拍 —— 入列時人在、四秒內走掉就不出聲")
    func presenceLostInsideTheCoalesceWindow() {
        // 少了這一則，上一則可以被一個「永遠回 .audible」的實作騙過去。
        var e = NotificationEngine()
        _ = e.update(input(tree([.running, .running]), presence: .atKeyboard), now: at(0))
        _ = e.update(input(tree([.finished, .finished], runStatus: "completed"),
                           presence: .atKeyboard), now: at(3))
        _ = e.update(input(tree([.finished, .finished], runStatus: "completed"),
                           presence: .away), now: at(6))
        #expect(audibility(e.flush(now: at(7))) == .silent(.noOneWatching))
    }

    @Test("離開 flush 的每一則 T2 都已經有裁決 —— 沒有任何一則帶著 undecided 走出去")
    func nothingEscapesUndecided() {
        // 抓的是「將來多開一條 flush 路徑而忘了裁決」，而它的失敗形式是安靜的。
        var e = NotificationEngine()
        var all: [NotificationEvent] = []
        all += drain(&e, presence: .atKeyboard, workflowId: "wf_1", startingAt: 0)
        all += drain(&e, presence: .away, workflowId: "wf_2", startingAt: 100)
        all += drain(&e, presence: .atKeyboard, workflowId: "wf_3",
                     runStatus: "failed", startingAt: 200)
        #expect(all.count == 3)
        for event in all {
            guard case .batchDrained(let b) = event else { continue }
            #expect(b.audibility != .undecided)
        }
    }

    @Test("一小時內第四則只掉聲音，事件照發")
    func fourthDrainInAnHourLosesOnlyTheSound() {
        // 最小間隔／冷卻期型的實作會在這裡紅（它會把第二則就吃掉），
        // 「整則吞掉」的實作也會紅（count 不再是 1）。
        var e = NotificationEngine()
        for (i, id) in ["wf_1", "wf_2", "wf_3"].enumerated() {
            let events = drain(&e, presence: .atKeyboard, workflowId: id,
                               startingAt: Double(i) * 100)
            #expect(audibility(events) == .audible)
        }
        let fourth = drain(&e, presence: .atKeyboard, workflowId: "wf_4", startingAt: 300)
        #expect(fourth.count == 1)
        #expect(audibility(fourth) == .silent(.budgetSpent))
    }

    @Test("預算是滾動視窗，不是整點歸零")
    func budgetWindowIsRollingNotCalendar() {
        var e = NotificationEngine()
        for (i, id) in ["wf_1", "wf_2", "wf_3"].enumerated() {
            _ = drain(&e, presence: .atKeyboard, workflowId: id, startingAt: Double(i))
        }
        // 第一筆是在 at(7) 扣的（flush 的時刻）。
        let stillBlocked = drain(&e, presence: .atKeyboard, workflowId: "wf_4",
                                 startingAt: SoundBudget.window - 1)
        #expect(audibility(stillBlocked) == .silent(.budgetSpent))
        let allowed = drain(&e, presence: .atKeyboard, workflowId: "wf_5",
                            startingAt: SoundBudget.window + 1)
        #expect(audibility(allowed) == .audible)
    }

    @Test("被在場閘擋掉的不扣預算 —— 一夜沒人在不可以吞掉早上的第一聲")
    func awayDrainsDoNotSpendBudget() {
        // 最容易寫錯的一則，而且反例就在資料裡：〔實測〕54% 的排空發生在
        // 23:00–08:00。無條件扣款、或把預算排在在場之前的實作都會紅。
        var e = NotificationEngine()
        for i in 0..<10 {
            _ = drain(&e, presence: .away, workflowId: "wf_night\(i)",
                      startingAt: Double(i) * 30)
        }
        let morning = drain(&e, presence: .atKeyboard, workflowId: "wf_morning",
                            startingAt: 400)
        #expect(audibility(morning) == .audible)
    }

    @Test("失敗的那批不扣預算 —— 它本來就不出聲")
    func failedDrainsDoNotSpendBudget() {
        // 「先扣款再看 outcome」的實作會讓第四則真完成被吃掉。
        var e = NotificationEngine()
        for i in 0..<3 {
            _ = drain(&e, presence: .atKeyboard, workflowId: "wf_fail\(i)",
                      runStatus: "failed", startingAt: Double(i) * 30)
        }
        let real = drain(&e, presence: .atKeyboard, workflowId: "wf_ok", startingAt: 200)
        #expect(audibility(real) == .audible)
    }

    @Test("靜音期間排空不扣預算 —— 解除靜音後拿回完整額度")
    func mutedDrainsDoNotSpendBudget() {
        // 抓把裁決放在 isMuted 檢查**之前**的實作。
        var e = NotificationEngine()
        e.mute(until: at(500))
        for i in 0..<3 {
            let swallowed = drain(&e, presence: .atKeyboard, workflowId: "wf_muted\(i)",
                                  startingAt: Double(i) * 30)
            #expect(swallowed.isEmpty)
        }
        e.unmute()
        for i in 0..<3 {
            let events = drain(&e, presence: .atKeyboard, workflowId: "wf_after\(i)",
                               startingAt: 600 + Double(i) * 30)
            #expect(audibility(events) == .audible)
        }
    }

    @Test("T1 不受這道閘影響 —— 人不在的時候等待事件照樣送出去")
    func t1UntouchedByTheBatchGate() {
        // 有人在等你是唯一可以打斷你的一級。抓「把閘做成 flush 的全域音效閘」
        // 的實作 —— 那種版本會讓 T1 在人不在時整個消失，而 T1 的正確行為是
        // 留著等人回來（presenter 的 deferred），不是丟掉。
        var e = NotificationEngine()
        _ = e.update(NotificationInput(sessions: [], trees: [:], usage: nil,
                                       presence: .away), now: at(0))
        e.forceEnqueueForTesting(sessionId: "S9", now: at(3))
        let events = e.flush(now: at(8))
        #expect(events.count == 1)
        guard case .waiting = events[0] else {
            Issue.record("T1 被 T2 的閘吃掉了"); return
        }
    }
}

// ═══════════════════════════════════════════════════════════════
//  T3：額度分級降級
// ═══════════════════════════════════════════════════════════════

/// ⚠️ 這裡**刻意偏離設計文件**：不用 70%／90%，改用 `QuotaTier` 的降級。
///
/// `GlyphState` 已經寫死一條規則 ——「門檻只能定義在 `QuotaTier.forRemaining`」。
/// 再引進第二組門檻，就會出現「圖示已經變紅、但通知說你還在 70% 那一格」
/// 這種不一致，而且不會有人馬上發現。訊號與顏色要講同一件事。
@Suite("NotificationEngine — T3 額度分級")
struct NotificationT3Tests {

    let t0 = Date(timeIntervalSince1970: 1_789_660_000)
    func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    func usage(fiveHourUsed: Int?, freshness: Freshness = .live) -> UsageSnapshot {
        UsageSnapshot(
            fiveHour: fiveHourUsed.map { UsageWindow(percent: $0, resetsAt: at(3600)) },
            sevenDay: nil, perModel: [:], freshness: freshness, fetchedAt: t0)
    }

    func input(_ u: UsageSnapshot?, presence: Presence = .atKeyboard) -> NotificationInput {
        NotificationInput(sessions: [], trees: [:], usage: u, presence: presence)
    }

    @Test("分級變差發一次 —— 而且只有那一次")
    func tierDegradationFiresOnce() throws {
        var e = NotificationEngine()
        _ = e.update(input(usage(fiveHourUsed: 20)), now: at(0))      // 剩 80%，comfortable
        #expect(e.flush(now: at(4)).isEmpty)

        _ = e.update(input(usage(fiveHourUsed: 60)), now: at(30))     // 剩 40%，tight
        let events = e.flush(now: at(34))
        #expect(events.count == 1)
        guard case .quotaTier(let q) = try #require(events.first) else {
            Issue.record("不是 quotaTier 事件"); return
        }
        #expect(q.from == .comfortable)
        #expect(q.to == .tight)

        _ = e.update(input(usage(fiveHourUsed: 65)), now: at(60))     // 還在 tight
        #expect(e.flush(now: at(64)).isEmpty)
    }

    @Test("分級變好不發 —— 好消息不需要打斷你")
    func recoveryIsSilent() {
        var e = NotificationEngine()
        _ = e.update(input(usage(fiveHourUsed: 90)), now: at(0))      // critical
        _ = e.flush(now: at(4))
        _ = e.update(input(usage(fiveHourUsed: 10)), now: at(30))     // 重置了
        #expect(e.flush(now: at(34)).isEmpty)
    }

    @Test("第一次看到的分級不發 —— 那是現況，不是變化")
    func firstObservationIsNotAChange() {
        var e = NotificationEngine()
        _ = e.update(input(usage(fiveHourUsed: 95)), now: at(0))
        #expect(e.flush(now: at(4)).isEmpty)
    }

    @Test("讀數過期就什麼都不發 —— 對不可信的數字發通知比不發更糟")
    func expiredReadingNeverFires() {
        var e = NotificationEngine()
        _ = e.update(input(usage(fiveHourUsed: 20)), now: at(0))
        _ = e.flush(now: at(4))
        _ = e.update(input(usage(fiveHourUsed: 90, freshness: .expired)), now: at(30))
        #expect(e.flush(now: at(34)).isEmpty)
    }

    @Test("沒有讀數不等於 0 —— 從有讀數變成沒讀數不發")
    func missingReadingIsNotZero() {
        var e = NotificationEngine()
        _ = e.update(input(usage(fiveHourUsed: 20)), now: at(0))
        _ = e.flush(now: at(4))
        _ = e.update(input(nil), now: at(30))
        #expect(e.flush(now: at(34)).isEmpty)
    }
}

// ═══════════════════════════════════════════════════════════════
//  靜音
// ═══════════════════════════════════════════════════════════════

/// **不自建安靜時段排程器。** macOS Focus 已經做了，第二個排程器正是
/// 「明明開了勿擾卻在半夜三點響」的成因。這裡只做手動靜音。
///
/// 而且 Focus 狀態實測**讀不到**（`~/Library/DoNotDisturb/DB/Assertions.json`
/// 受 TCC 保護，也沒有公開 API），所以手動靜音是唯一的防線。
@Suite("NotificationEngine — 靜音")
struct NotificationMuteTests {

    let t0 = Date(timeIntervalSince1970: 1_789_660_000)
    func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    func session(_ id: String, _ status: SessionStatus, _ statusAt: Date?) -> LiveSession {
        LiveSession(session: ClaudeSession(
            pid: 999, sessionId: id, cwd: "/p/usage",
            startedAt: t0.addingTimeInterval(-3600), status: status,
            statusUpdatedAt: statusAt))
    }

    func input(_ s: [LiveSession], presence: Presence = .atKeyboard) -> NotificationInput {
        NotificationInput(sessions: s, trees: [:], usage: nil, presence: presence)
    }

    @Test("靜音期間全部三級都不發")
    func muteSuppressesEverything() {
        var e = NotificationEngine()
        e.mute(until: at(3600))
        _ = e.update(input([session("S1", .busy, at(-10))]), now: at(-10))
        _ = e.update(input([session("S1", .waiting(.inputNeeded), at(0))]), now: at(0))
        #expect(e.flush(now: at(4)).isEmpty)
    }

    @Test("被靜音的事件是丟掉不是排隊 —— 解除靜音不會爆出一串")
    func mutedEventsAreDroppedNotQueued() {
        var e = NotificationEngine()
        e.mute(until: at(100))
        _ = e.update(input([session("S1", .busy, at(-10))]), now: at(-10))
        _ = e.update(input([session("S1", .waiting(.inputNeeded), at(0))]), now: at(0))
        #expect(e.flush(now: at(4)).isEmpty)

        // 靜音結束，同一個還在等的 episode 不會補發
        _ = e.update(input([session("S1", .waiting(.inputNeeded), at(0))]), now: at(200))
        #expect(e.flush(now: at(204)).isEmpty)
    }

    @Test("靜音期間狀態照樣往前走 —— 解除後的新事件才發")
    func stateAdvancesWhileMuted() {
        var e = NotificationEngine()
        e.mute(until: at(100))
        _ = e.update(input([session("S1", .busy, at(-10))]), now: at(-10))
        _ = e.update(input([session("S1", .waiting(.inputNeeded), at(0))]), now: at(0))
        _ = e.flush(now: at(4))

        // 解除後的**新** episode 才會發
        _ = e.update(input([session("S1", .waiting(.permissionPrompt), at(200))]), now: at(200))
        #expect(e.flush(now: at(204)).count == 1)
    }

    @Test("靜音到期就自己解除，不必有人來清")
    func muteExpiresOnItsOwn() {
        var e = NotificationEngine()
        e.mute(until: at(50))
        #expect(e.isMuted(at: at(49)) == true)
        #expect(e.isMuted(at: at(51)) == false)
    }
}
