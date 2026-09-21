import Foundation

/// 餵給引擎的一拍。做成 struct 而不是六個參數，之後多一個欄位才不會是每個
/// 測試都要改的簽章變更。
public struct NotificationInput: Equatable, Sendable {
    public let sessions: [LiveSession]
    public let trees: [String: AgentTree]
    public let usage: UsageSnapshot?
    /// 這一拍「人在不在」。**原始三訊號，不是算好的 Bool** —— 判斷留在 Core
    /// 才測得到。見 `Presence`。
    public let presence: Presence

    /// ⚠️ `presence` **不給預設值**。呼叫點實測只有七個（`DataStore` 與
    /// `TraceAlerts` 各一，五個單行測試 helper），而不給預設值買到的是：
    /// 漏接線時是編譯錯誤，不是一個沒有人會發現的行為決定。
    public init(sessions: [LiveSession], trees: [String: AgentTree],
                usage: UsageSnapshot?, presence: Presence) {
        self.sessions = sessions
        self.trees = trees
        self.usage = usage
        self.presence = presence
    }
}

/// 決定「現在該不該通知，以及通知什麼」。純狀態機，沒有計時器、沒有 I/O、
/// 沒有 AppKit。時間一律用參數注入 —— Core 裡不可以出現 `Date()`。
///
/// 形狀照抄 `BreathController`（同一個作者、同一種問題），兩處刻意不同：
///   1. **回傳 `[NotificationEvent]` 而不是 `Bool`。** `BreathController` 一觸發就
///      早退，所以它一次只回得了一件事；這裡 session A 的 T1 與 workflow B 的 T2
///      可以在同一拍發生。
///   2. **狀態是 keyed map 而不是純量**，因為去重是 per session／per workflowId。
///
/// ### 為什麼分成 update 與 flush 兩步
/// 設計文件要求「同類事件 ≥3 則合成一則摘要，合併視窗 4 秒」。`update` 觀察並
/// 把新事件放進待發區，`flush` 把過了視窗的送出去。呼叫端每一拍兩個都叫。
///
/// **代價講在前面：單一 T1 也會延後最多 4 秒。** 可以接受，因為選單列圖示在
/// **同一拍**就已經變琥珀並開始呼吸（`BreathController` 吃的是同一份資料）——
/// 瞬時訊號早就發出去了，4 秒的視窗只用在比較重的那個打斷上。
public struct NotificationEngine: Equatable, Sendable {

    /// T1 重推的時點（自事件起算）。恰好一次，之後永遠安靜。
    /// 與 `Breath.scheduledDelays` 的第二個值刻意對齊 —— 圖示與浮窗在同一個
    /// 時間點再喊一次，而不是各喊各的。
    public static let t1RepeatDelays: [TimeInterval] = [300]
    /// 相同去重鍵的抑制窗。
    public static let dedupWindow: TimeInterval = 60
    /// 合併視窗。
    public static let coalesceWindow: TimeInterval = 4
    /// 幾則以上才合併。**兩個不合併。**
    public static let coalesceThreshold = 3
    /// key 消失後要撐多久才算真的沒了。
    ///
    /// ⚠️ 這是 Stage 5 唯一必須比 `BreathController` **更保守**的地方 ——
    /// 它是 `blockedCount == 0` 就當場重置，但這裡「讀不到」與「結束了」
    /// 在資料上長得一模一樣，當場重置會把一次讀檔失敗說成「整批完成」。
    public static let absenceGrace: TimeInterval = 30
    public static let absenceTicks = 2

    // ── 使用者直接設定的狀態 ────────────────────────────────────

    private(set) public var mutedUntil: Date?

    // ── 觀測狀態 ───────────────────────────────────────────────

    private var waits: [String: WaitState] = [:]
    private var batches: [String: BatchState] = [:]
    private var lastTier: QuotaTier?
    private var pending: [PendingEvent] = []
    /// 合併視窗的錨點 —— 第一則事件進到空的待發區時開始計時。
    ///
    /// **每則各自計時是錯的**：第一則在 t=0、第三則在 t=3，t=4 flush 時前兩則熟了、
    /// 第三則還沒，於是「三個一起卡住」會變成「兩則 + 一則」。視窗是一個視窗，
    /// 不是每則一個。
    private var coalesceOpenedAt: Date?
    /// 去重鍵 → 最後發出時間。
    ///
    /// ⚠️ **一定要清。** episode 鍵是 `statusUpdatedAt` 的毫秒數，所以每一次等待
    /// 都是一個**新**鍵；不清的話，一台開著幾週的機器會累積幾萬筆再也不會被
    /// 查到的條目。這不是崩潰等級的洩漏，但它是那種永遠不會有人回來修的洩漏。
    private var lastEmitted: [String: Date] = [:]
    /// 還沒觀測過任何一拍。第一拍只記錄，不發任何東西。
    private var seeded = false
    /// 最後一拍看到的在場狀態。`update` 記下，`flush` 用它裁決。
    ///
    /// **為什麼取 flush 那一拍而不是入列那一拍：** 聲音發生在送出的那一刻，
    /// 而合併視窗 4 秒 > 輪詢 3 秒 —— 「在視窗裡走掉或回來」是真的會發生的事。
    ///
    /// ⚠️ 它依賴呼叫端**同一個 `now` 裡先 `update` 再 `flush`**（`DataStore` 與
    /// `TraceAlerts` 今天都是），型別上沒有任何東西擋得住單獨呼叫 `flush` ——
    /// 那樣會沿用上一拍的在場，而且不會有任何抱怨。
    ///
    /// 初值刻意是「三個訊號都還沒讀到」：它的 `worthSounding` 是 false，
    /// 所以在接線之前寧可安靜。
    private var lastPresence = Presence(screenLocked: false, screensAsleep: false,
                                        idleSeconds: nil)
    /// T2 音效的一小時上限。見 `SoundBudget`。
    private var batchSounds = SoundBudget()

    /// 額度分級的邊界。T3 是在分級**變了的那一刻**發的，所以它跟著使用者調。
    ///
    /// ⚠️ 走建構子注入而不是 `NotificationInput` —— 門檻不該有「哪一拍的值算數」
    /// 這個問題（`lastPresence` 那一段的 ⚠️ 講的就是那個危險）。
    private let quotaThresholds: QuotaThresholds

    public init(quotaThresholds: QuotaThresholds = .standard) {
        self.quotaThresholds = quotaThresholds
    }

    // ── 內部狀態型別 ───────────────────────────────────────────

    struct WaitState: Equatable, Sendable {
        /// 這次等待事件的身分。見下方 `episodeKey`。
        var episode: String
        var onsetAt: Date
        /// 已經發過的排程重推（索引對應 `t1RepeatDelays`）。
        var firedRepeats: Set<Int>
        /// 已經把第一次放進待發區了。
        var announced: Bool
        /// 最後一次真的在讀取結果裡看到它。見 `observeWaiting` 的寬限說明。
        var lastSeen: Date
        var missedTicks: Int
    }

    struct BatchState: Equatable, Sendable {
        var total: Int
        /// **單調不減。** journal 暫時讀不到讓 finishedCount 掉下來，不可以
        /// 讓一批已經排空的又變回沒排空。
        var peakFinished: Int
        /// 看過它「還沒終結」的樣子。沒看過就不可以宣告「完成了」——
        /// 這一條擋掉「app 啟動前就已經跑完的那批」：第一次就看到 run 狀態檔
        /// 已經是終結值的話，這裡永遠是 false。
        var everObservedIncomplete: Bool
        var lastSeen: Date
        var missedTicks: Int
        var notified: Bool
    }

    struct PendingEvent: Equatable, Sendable {
        var event: NotificationEvent
        var enqueuedAt: Date
    }

    // ── 去重鍵 ─────────────────────────────────────────────────

    /// ⚠️ 穩定字串，不是 `hashValue`。理由見 `NotificationEvent.dedupKey`。
    public static func waitingDedupKey(sessionId: String, episode: String) -> String {
        "\(sessionId)|waiting|\(episode)"
    }

    /// 一次等待事件的身分。
    ///
    /// **為什麼不是「看到它從非等待變成等待」：** 三秒輪詢常常整拍錯過中間那段
    /// busy —— 你回答完一個問題，Claude 馬上又要求批准工具，
    /// `waiting → busy → waiting` 可能發生在同一拍之內。靠轉換判斷，會讓實際
    /// 使用上**最常見**的那一種等待完全不發通知。
    /// `statusUpdatedAt` 就是那個判別器，而且它本來就在 `ClaudeSession` 裡。
    /// 舊版本沒有這個欄位時才退回轉換判定。
    static func episodeKey(_ s: LiveSession) -> String {
        guard let t = s.session.statusUpdatedAt else { return "transition" }
        // ⚠️ **不可以寫 `Int(...)`。** 這個數字來自磁碟上的 JSON，只要它大到
        // 超過 Int.max（或是 NaN），`Int(Double)` 會直接 trap —— 不是丟例外，
        // 是整個行程死掉。實測 1e18 就打得死。Double 自己的字串表示不會 trap，
        // 而且對同一個值是穩定的，當識別碼夠用了。
        return String(t.timeIntervalSince1970)
    }

    /// 這次等待**實際**開始的時間。
    ///
    /// 與排程用的 `onsetAt` 刻意分開：`onsetAt` 是「我們什麼時候開始講這件事」
    /// （T+300 的重推從它算起），`waitStart` 是「它什麼時候開始等」
    /// （浮窗上那個往上數的秒數，以及合併後誰排前面，都靠它）。
    /// 兩者在見證到的轉換上幾乎相同，但在合併多個 session 時差很多 ——
    /// 用 onsetAt 排序會讓三個同時被看到的 session 全部並列，
    /// 「先處理擋最久的」就變成一句空話。
    static func waitStart(_ s: LiveSession, fallback: Date) -> Date {
        s.session.statusUpdatedAt ?? fallback
    }

    // ── 靜音 ───────────────────────────────────────────────────

    public mutating func mute(until date: Date) { mutedUntil = date }
    public mutating func unmute() { mutedUntil = nil }

    public func isMuted(at now: Date) -> Bool {
        guard let mutedUntil else { return false }
        return now < mutedUntil
    }

    /// 從磁碟讀回來時用。見 `NotifyState`。
    public mutating func restore(mutedUntil: Date?) { self.mutedUntil = mutedUntil }

    // ── 觀察這一拍 ─────────────────────────────────────────────

    /// 觀察，並把新事件放進待發區。
    /// - Returns: 這一拍**立刻**就該送出去的事件。目前一律是空的（全部都要過
    ///   合併視窗），保留回傳值是為了讓呼叫端的形狀不必因為未來的例外而改。
    @discardableResult
    public mutating func update(_ input: NotificationInput, now: Date) -> [NotificationEvent] {
        defer { seeded = true }
        // 只記錄，不判斷 —— 判斷在 flush 的最後一步。
        lastPresence = input.presence
        observeWaiting(input.sessions, now: now)
        observeBatches(input.trees, now: now)
        observeQuota(input.usage, now: now)
        return []
    }

    /// 把過了合併視窗的待發事件送出去。
    public mutating func flush(now: Date) -> [NotificationEvent] {
        guard !pending.isEmpty else { return [] }

        // 靜音：**丟掉**，不排隊。排隊的話解除靜音會一次爆出一串，
        // 而那一串講的全都是你靜音那段時間裡的舊消息。
        guard !isMuted(at: now) else { pending.removeAll(); coalesceOpenedAt = nil; return [] }

        // ⚠️ **送出前重新確認那個等待還在。**
        //
        // 合併視窗是 4 秒、輪詢是 3 秒 —— 在視窗裡把問題回答掉是很正常的事。
        // 不重新確認的話，浮窗會對著一個你剛剛才回答過的問題喊，
        // 而那正是這個 app 最快被刪掉的方式。
        pending.removeAll { p in
            guard case .waiting(let a) = p.event else { return false }
            guard let st = waits[a.primary.sessionId] else { return true }   // 已經不在等了
            return st.episode != a.primary.episode                            // 已經是下一個問題了
        }
        if pending.isEmpty { coalesceOpenedAt = nil; return [] }

        // 重推不進合併視窗：排程性的重推按定義就是孤零零的一則，
        // 沒有東西可以跟它合併，讓它多等 4 秒只是讓那個時點變得不準。
        let repeats = pending.filter { if case .waiting(let a) = $0.event { return a.isRepeat }
                                       return false }
        let windowElapsed = coalesceOpenedAt.map {
            now.timeIntervalSince($0) >= Self.coalesceWindow
        } ?? false

        guard windowElapsed || !repeats.isEmpty else { return [] }

        let ripe = windowElapsed ? pending : repeats
        if windowElapsed {
            pending.removeAll()
            coalesceOpenedAt = nil
        } else {
            pending.removeAll { p in repeats.contains { $0.event == p.event } }
            if pending.isEmpty { coalesceOpenedAt = nil }
        }

        var out: [NotificationEvent] = []

        // T1 要合併，其餘各走各的。
        var waitingSessions: [WaitingSession] = []
        for p in ripe {
            switch p.event {
            case .waiting(let a):
                if a.isRepeat {
                    out.append(p.event)
                } else {
                    waitingSessions.append(contentsOf: a.sessions)
                }
            default:
                out.append(p.event)
            }
        }

        // 等最久的排最前面 —— 先處理擋最久的。
        let sorted = waitingSessions.sorted { $0.since < $1.since }
        if let first = sorted.first {
            if sorted.count >= Self.coalesceThreshold {
                out.append(.waiting(WaitingAlert(primary: first,
                                                 others: Array(sorted.dropFirst()),
                                                 coalesced: true, isRepeat: false)))
            } else {
                for s in sorted {
                    out.append(.waiting(WaitingAlert(primary: s, coalesced: false, isRepeat: false)))
                }
            }
        }

        // 超過去重窗的條目再也不會影響任何判斷，清掉。
        lastEmitted = lastEmitted.filter { now.timeIntervalSince($0.value) < Self.dedupWindow }

        // 去重最後才做，這樣合併後的那一則也拿得到自己的鍵。
        let delivered = out.filter { event in
            // 重推的那一次刻意不受去重窗影響 —— 它就是同一個鍵，而且就是要再講一次。
            if case .waiting(let a) = event, a.isRepeat {
                lastEmitted[event.dedupKey] = now
                return true
            }
            let key = event.dedupKey
            if let last = lastEmitted[key], now.timeIntervalSince(last) < Self.dedupWindow {
                return false
            }
            lastEmitted[key] = now
            return true
        }

        // 裁決放在**去重之後**：只有真的會走出這扇門的事件才需要決定音量，
        // 也才可以動用預算。被去重窗吃掉的、被靜音整批丟掉的，一格都不扣。
        var decided: [NotificationEvent] = []
        decided.reserveCapacity(delivered.count)
        for event in delivered { decided.append(decide(event, now: now)) }
        return decided
    }

    // ── 出不出聲 ───────────────────────────────────────────────

    /// 替一則要送出去的事件蓋上音量裁決。T1／T3 原樣通過。
    ///
    /// **T1 不走這裡**：有人在等你是唯一可以打斷你的一級，它的通道選擇
    /// （浮窗 vs 留著等人回來 + osascript）留在 presenter，因為那是路由，
    /// 不是「該不該發」。
    private mutating func decide(_ event: NotificationEvent, now: Date) -> NotificationEvent {
        guard case .batchDrained(let b) = event else { return event }
        return .batchDrained(b.with(audibility: audibility(for: b, now: now)))
    }

    /// 順序就是它的意思：先看這一則**本來**該不該出聲，再看有沒有人聽得到。
    private mutating func audibility(for b: BatchAlert, now: Date) -> Audibility {
        // 失敗的那批不出聲。T2 只有圖示與聲音、沒有文字，所以「措辭要是失敗
        // 不是完成」這條承諾只剩聲音的有無可以兌現。
        guard b.outcome == .completed else { return .silent(.failedOutcome) }
        // 對著一台鎖上、螢幕睡著、閒置 866 秒的機器播音效 —— 2026-09-19 實測
        // 抓到的就是這一格。〔代理推算〕在場閘會擋掉 26 聲裡的 20 聲。
        guard lastPresence.worthSounding else { return .silent(.noOneWatching) }
        // 預算**排在最後**，所以只有真的會出聲的才扣款。被 outcome 擋的、
        // 被在場擋的、被靜音整批丟掉的（`flush` 在更前面就 return 了），
        // 一格都不進帳 —— 否則〔實測〕23:00–08:00 那 54% 會吃掉隔天早上的第一聲。
        guard batchSounds.consumeIfPossible(at: now) else { return .silent(.budgetSpent) }
        return .audible
    }

    /// T2 音效這一小時還剩幾格。**診斷用，非 mutating。**
    ///
    /// ⚠️ `--trace-alerts` 讀到的是它自己那個行程裡的**影子引擎**，
    /// 不是選單列上那個 app 的。印出來時一定要標明。
    public func batchSoundBudgetRemaining(at now: Date) -> Int {
        batchSounds.remaining(at: now)
    }

    // ── T1 ────────────────────────────────────────────────────

    private mutating func observeWaiting(_ sessions: [LiveSession], now: Date) {
        var live = Set<String>()
        // 這一拍**看到**的所有 session，不管它在不在等。
        // 「看到它不在等了」與「整個沒看到它」是完全不同的兩件事，
        // 前者是正面證據（當場清），後者不是（要寬限）。混在一起就會
        // 兩邊都做錯一種。
        let present = Set(sessions.map(\.session.sessionId))

        for s in sessions where s.needsHuman {
            let id = s.session.sessionId
            live.insert(id)
            let episode = Self.episodeKey(s)

            if var st = waits[id] {
                st.lastSeen = now
                st.missedTicks = 0
                waits[id] = st
                if st.episode != episode {
                    // 同一個 session 的新事件。中間那段 busy 沒被看到也算數。
                    waits[id] = WaitState(episode: episode, onsetAt: now,
                                          firedRepeats: [], announced: true,
                                          lastSeen: now, missedTicks: 0)
                    enqueueWaiting(s, since: Self.waitStart(s, fallback: now),
                                   episode: episode, isRepeat: false, now: now)
                    continue
                }
                // 同一個事件持續中：只剩排程重推。
                //
                // ⚠️ `announced` 是這裡的閘。第一次觀測不發的那些（app 啟動時
                // 就已經在等的），如果照常安排重推，T+300 就會冒出一則 ——
                // 那等於「不發」只是延後了五分鐘，而且冒出來的還被當成重推，
                // 連聲音都不會有，使用者只會看到一扇沒有來由的窗。
                for (i, delay) in Self.t1RepeatDelays.enumerated()
                where st.announced && now.timeIntervalSince(st.onsetAt) >= delay
                      && !st.firedRepeats.contains(i) {
                    st.firedRepeats.insert(i)
                    waits[id] = st
                    enqueueWaiting(s, since: Self.waitStart(s, fallback: st.onsetAt),
                                   episode: episode, isRepeat: true, now: now)
                    break
                }
                waits[id] = st
            } else {
                // 沒看過這個 session 在等。
                //
                // ⚠️ **第一次觀測不發。** app 剛啟動時就已經在等的 session，
                // 我們沒有見證它進入等待，不算一次我們見證的事件。少掉的只有
                // 那一次打斷 —— 圖示本來就已經是琥珀色而且在呼吸，資訊一點都沒少。
                // 這條規則讓「啟動時對著三個 session 同時尖叫」在結構上不可能發生，
                // 而開發期間 make_app.sh 會不斷重啟這個 app。
                waits[id] = WaitState(episode: episode, onsetAt: now,
                                      firedRepeats: [], announced: seeded,
                                      lastSeen: now, missedTicks: 0)
                if seeded {
                    enqueueWaiting(s, since: Self.waitStart(s, fallback: now),
                                   episode: episode, isRepeat: false, now: now)
                }
            }
        }

        // ⚠️ **這裡也要寬限期，理由和 T2 一模一樣：不存在不等於解除。**
        //
        // 存活閘打嗝、`contentsOfDirectory` 失敗，都會讓一個還在等的 session
        // 從某一拍的讀取結果裡整個消失。當場清掉的話，它回來時 statusUpdatedAt
        // 一模一樣，卻會被當成新事件 —— 同一個問題再喊一次（**而且會出聲**，
        // 因為那不是重推），連「恰好一次」的重推額度都發回去。
        //
        // 這段註解曾經寫著「最壞的情況是下一次等待被當成新事件，而它本來就是
        // 新事件」。那是錯的，而且是被一支探針證明錯的：漏看一拍之後，
        // 同一個 episode 在 t+9 再喊一次，t+305 又多一次重推。
        for (id, var st) in waits where !live.contains(id) {
            // 看到它了，而且它不在等 —— 這是解除，當場清。
            if present.contains(id) { waits.removeValue(forKey: id); continue }
            st.missedTicks += 1
            if st.missedTicks >= Self.absenceTicks,
               now.timeIntervalSince(st.lastSeen) >= Self.absenceGrace {
                waits.removeValue(forKey: id)
            } else {
                waits[id] = st
            }
        }
    }

    private mutating func enqueueWaiting(_ s: LiveSession, since: Date, episode: String,
                                         isRepeat: Bool, now: Date) {
        let w = WaitingSession(
            sessionId: s.session.sessionId, pid: s.session.pid, project: s.project,
            name: s.session.name, waitingFor: s.waitingFor, since: since,
            cwd: s.session.cwd, episode: episode)
        let event = NotificationEvent.waiting(
            WaitingAlert(primary: w, coalesced: false, isRepeat: isRepeat))
        // 同一拍被呼叫兩次時不要排兩則 —— refresh() 有六個呼叫點，
        // 開面板的那一下會在幾毫秒內連呼兩次。
        guard !pending.contains(where: { $0.event == event }) else { return }
        enqueue(event, now: now)
    }

    /// 進待發區，並在需要時開啟合併視窗。
    private mutating func enqueue(_ event: NotificationEvent, now: Date) {
        if pending.isEmpty { coalesceOpenedAt = now }
        pending.append(PendingEvent(event: event, enqueuedAt: now))
    }

    // ── T2 ────────────────────────────────────────────────────

    private mutating func observeBatches(_ trees: [String: AgentTree], now: Date) {
        var seen = Set<String>()

        for (sessionId, tree) in trees {
            for g in tree.workflows {
                let key = "\(sessionId)|\(g.workflowId)"
                seen.insert(key)

                var st = batches[key] ?? BatchState(
                    total: 0, peakFinished: 0, everObservedIncomplete: false,
                    lastSeen: now, missedTicks: 0, notified: false)

                // 兩個都取看過的最大值，**然後拿最大值去比**。
                //
                // 只看當下那一拍是不夠的：meta 檔沒通過新鮮度閘、或目錄讀一半，
                // group 就會少掉幾隻 —— 「5 隻裡完成 2 隻」會在縮到 2 隻的那一拍
                // 變成「2/2 全部完成」。而 finishedCount 自己也會掉（journal 暫時
                // 讀不到，那幾隻變回 .unknown），所以進度也必須是單調的。
                st.total = max(st.total, g.total)
                st.peakFinished = max(st.peakFinished, g.finishedCount)
                st.lastSeen = now
                st.missedTicks = 0

                // **「排空」的正面證據是 run 狀態檔，不是 journal 的數字。**
                //
                // `<sessionId>/workflows/<wf_id>.json` 只在 run 終結時寫一次
                // 〔實測 n=32：全部 mtime == birthtime，而且 birthtime 從來不早於
                // 最後一次 journal 寫入；執行中的 workflow 在磁碟上根本還沒有這個檔〕。
                // 所以「檔案在、而且 status 是終結值」＝「整個 workflow script 回來了」，
                // 這正是 Task 5.5 要的那種正面證據。
                //
                // ⚠️ **只看 journal 的 `finishedCount == total` 會在錯的時刻宣告。**
                // `total` 只數**目前目錄裡存在的 meta 檔**，所以多階段 pipeline 的
                // 階段交界（上一階段全部收尾、下一階段還沒 spawn）當場就滿足它 ——
                // 〔實測〕磁碟上 32 個 workflow 有 25 個真的出現過這個窗口，
                // 8 個 ≥3 秒，也就是必定被 3 秒輪詢取樣到。
                //
                // 兩個條件都留著：run 終結時 `AgentTreeBuilder` 會把每一隻折成
                // `.finished`，所以 `peakFinished >= total` 在正常路徑上是自動成立的。
                // 它在這裡是第二道防線 —— 哪天那個折疊改了，這裡會安靜地**少報**，
                // 而不是謊報。
                let terminated = WorkflowRunState.terminalStatuses.contains(g.runStatus ?? "")
                let complete = terminated && st.total > 0 && st.peakFinished >= st.total
                if !complete { st.everObservedIncomplete = true }

                if complete && st.everObservedIncomplete && !st.notified {
                    st.notified = true
                    // run 自己說它被中止 → 完全不發。是你自己按的 TaskStop，你知道。
                    // 中止會把每一隻 agent 折成 .finished，所以少了 runStatus，
                    // 這裡會對著一個你停掉的 run 說「全部完成」。
                    if g.runStatus != "killed" {
                        let event = NotificationEvent.batchDrained(BatchAlert(
                            sessionId: sessionId, workflowId: g.workflowId,
                            latestPhase: g.latestPhase,
                            total: st.total,
                            outcome: g.runStatus == "failed" ? .failed : .completed,
                            // run 自己量的，不是我們看了多久。見 `WorkflowRunState.duration`。
                            runDuration: g.runDuration,
                            // 待發區裡一律是 .undecided，裁決在 flush 的最後一步。
                            // 理由見 `Audibility.undecided`：這個型別是 Equatable，
                            // 而三處 `pending.contains(where:)` 靠它擋重複入列。
                            audibility: .undecided))
                        if !pending.contains(where: { $0.event == event }) {
                            enqueue(event, now: now)
                        }
                    }
                }
                batches[key] = st
            }
        }

        // **不存在不等於排空。** key 消失的那一拍不可以刪掉狀態 ——
        // 讀檔失敗、存活閘打嗝、目錄還沒建好，都會讓整組憑空消失一拍。
        // 要連續 absenceTicks 次觀測不到**且**超過 absenceGrace 才過期。
        for (key, var st) in batches where !seen.contains(key) {
            st.missedTicks += 1
            if st.missedTicks >= Self.absenceTicks,
               now.timeIntervalSince(st.lastSeen) >= Self.absenceGrace {
                batches.removeValue(forKey: key)
            } else {
                batches[key] = st
            }
        }
    }

    // ── T3 ────────────────────────────────────────────────────

    private mutating func observeQuota(_ usage: UsageSnapshot?, now: Date) {
        // 過期或沒有讀數 → 什麼都不發，也**不要**把 lastTier 清掉。
        // 清掉的話，讀數回來的那一刻會被當成「第一次看到」而錯過真正的降級。
        guard let usage, usage.freshness != .expired else { return }

        let remaining = [usage.fiveHour, usage.sevenDay]
            .compactMap { $0.map { 1.0 - Double($0.percent) / 100.0 } }
            .min()
        guard let remaining else { return }
        let tier = QuotaTier.forRemaining(remaining, thresholds: quotaThresholds)

        defer { lastTier = tier }
        guard let previous = lastTier, previous != tier else { return }
        // 變好不發 —— 好消息不需要打斷你。
        guard Self.severity(tier) > Self.severity(previous) else { return }

        let event = NotificationEvent.quotaTier(QuotaTierAlert(from: previous, to: tier))
        guard !pending.contains(where: { $0.event == event }) else { return }
        enqueue(event, now: now)
    }

    private static func severity(_ t: QuotaTier) -> Int {
        switch t {
        case .comfortable: return 0
        case .tight: return 1
        case .critical: return 2
        }
    }

    // ── 測試專用 ───────────────────────────────────────────────

    /// 去重表現在有幾筆。只給測試用來確認它不會無限長大。
    var trackedDedupKeys: Int { lastEmitted.count }

    /// 只給測試用：直接把一則 T1 丟進待發區，用來單獨驗證去重窗。
    /// 正常路徑上不可能出現這個呼叫。
    public mutating func forceEnqueueForTesting(sessionId: String, now: Date) {
        let w = WaitingSession(sessionId: sessionId, pid: 1, project: "usage", name: nil,
                               waitingFor: .inputNeeded, since: now, cwd: "/p/usage",
                               episode: "fixed")
        // 等待狀態也要一起放進去：flush 會在送出前重新確認那個等待還在，
        // 沒有它的話這個 seam 造出來的事件會被當成「已經回答完了」而丟掉。
        waits[sessionId] = WaitState(episode: "fixed", onsetAt: now,
                                     firedRepeats: [], announced: true,
                                     lastSeen: now, missedTicks: 0)
        enqueue(.waiting(WaitingAlert(primary: w, coalesced: false, isRepeat: false)), now: now)
    }
}
