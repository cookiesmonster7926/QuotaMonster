import Foundation

/// 一則要送出去的通知。**純資料，沒有 AppKit 相依** —— 決定發什麼是 Core 的事，
/// 怎麼送（浮窗／音效／osascript）是 App 層的事。
public enum NotificationEvent: Equatable, Sendable {
    /// T1：有人在等你。唯一可以打斷你的一級。
    case waiting(WaitingAlert)
    /// T2：一次 workflow 扇出整批排空。
    case batchDrained(BatchAlert)
    /// T3：額度分級變差。只給圖示，不出聲也不浮窗。
    case quotaTier(QuotaTierAlert)

    /// 去重鍵。
    ///
    /// ⚠️ **一定是穩定字串，不可以用 `hashValue`。** Swift 的 `Hasher` 每個行程
    /// 重新設種子，存到磁碟的 hash 下次啟動就對不上，去重會**安靜地**停止運作 ——
    /// 而「安靜地停止運作」正是這種 bug 最難被發現的形式。
    public var dedupKey: String {
        switch self {
        case .waiting(let a):
            return a.coalesced
                // 鍵要帶 episode：同一組 session 的**下一輪**等待是新消息，
                // 只用 sessionId 的話它會被 60 秒的去重窗吞掉。
                ? "coalesced|waiting|"
                    + a.sessions.map { "\($0.sessionId)@\($0.episode)" }.sorted()
                        .joined(separator: ",")
                : NotificationEngine.waitingDedupKey(sessionId: a.primary.sessionId,
                                                     episode: a.primary.episode)
        case .batchDrained(let b):
            return "\(b.sessionId)|drained|\(b.workflowId)"
        case .quotaTier(let q):
            return "-|quota|\(q.to)"
        }
    }
}

// ── T1 ────────────────────────────────────────────────────────

/// 一個正在等你的 session，帶著浮窗與「跳過去」需要的全部東西。
public struct WaitingSession: Equatable, Sendable {
    public let sessionId: String
    /// 「跳過去」要靠它往上走 ppid 找到擁有這個 session 的 app。
    public let pid: Int32
    /// cwd 的最後一段。
    public let project: String
    /// Claude Code 自己取的名字（`usage-c9`）。VS Code 這種一個視窗裡開好幾個
    /// session 的宿主，使用者要靠它才知道該找哪一個分頁。
    public let name: String?
    public let waitingFor: WaitingFor?
    /// 這次等待從什麼時候開始。浮窗上那個往上數的秒數靠它。
    public let since: Date
    /// transcript 的路徑線索 —— App 層要拿它去讀「到底在問什麼」。
    public let cwd: String
    /// 這次等待事件的身分。見 `NotificationEngine` 的 episode 說明。
    public let episode: String

    public init(sessionId: String, pid: Int32, project: String, name: String?,
                waitingFor: WaitingFor?, since: Date, cwd: String, episode: String) {
        self.sessionId = sessionId
        self.pid = pid
        self.project = project
        self.name = name
        self.waitingFor = waitingFor
        self.since = since
        self.cwd = cwd
        self.episode = episode
    }
}

public struct WaitingAlert: Equatable, Sendable {
    /// 等最久的那一個。浮窗的英雄行、路徑、「跳過去」全都指向它。
    ///
    /// ⚠️ 刻意**不是** `[WaitingSession]` 的第一個元素。空的等待警示是一個
    /// 沒有意義的東西，而 UI 那邊要讀 `sessions[0]` —— 用陣列表示就等於
    /// 把一個會 crash 的狀態留在型別裡，然後靠每個呼叫端記得不要造出它。
    /// 拆成 primary + others 之後，那個狀態在結構上不存在。
    public let primary: WaitingSession
    /// 其餘的，仍然依等待時間排序。
    public let others: [WaitingSession]
    /// ≥3 個合成一則。**兩個不合併** —— 兩個各自完整比一則摘要有用。
    public let coalesced: Bool
    /// 這是 T+5 分鐘那一次的重推。之後就永遠安靜。
    public let isRepeat: Bool

    /// 等最久的排最前面 —— 先處理擋最久的那一個。
    public var sessions: [WaitingSession] { [primary] + others }

    public init(primary: WaitingSession, others: [WaitingSession] = [],
                coalesced: Bool, isRepeat: Bool) {
        self.primary = primary
        self.others = others
        self.coalesced = coalesced
        self.isRepeat = isRepeat
    }

    /// 只留下還在等的那些，重新排序、重新算合併旗標。全部都不在了就回 nil。
    ///
    /// **用在「人不在螢幕前」那條路上：** 警示被留著等人回來，而等的期間
    /// 使用者可能已經從別的地方回答了其中一個 —— 那一個不可以再出現在
    /// 補上的那扇窗裡，否則窗口會對著一個已經回答過的問題喊。
    ///
    /// ⚠️ **補上的那一扇 `isRepeat` 一律是 false。** `isRepeat` 的意思是
    /// 「你已經看過一次了」，presenter 會據此不出聲；但延後補上的這一扇
    /// 是使用者**第一次**看到它。
    public func retaining(_ stillWaiting: Set<String>) -> WaitingAlert? {
        let kept = sessions
            .filter { stillWaiting.contains($0.sessionId) }
            .sorted { $0.since < $1.since }
        guard let primary = kept.first else { return nil }
        return WaitingAlert(primary: primary, others: Array(kept.dropFirst()),
                            coalesced: kept.count >= NotificationEngine.coalesceThreshold,
                            isRepeat: false)
    }
}

// ── T2 ────────────────────────────────────────────────────────

/// 這一則 T2 到底會不會出聲，以及**為什麼不會**。
///
/// 理由要跟著事件走，不要另開一個側通道 —— 這樣 presenter 與
/// `--trace-alerts` 讀的是同一個值，診斷就不可能跟實際行為說不一樣的話。
///
/// ⚠️ 它**不進 `dedupKey`**：去重鍵回答「這是哪一件事」，不是「這一件事多大聲」。
public enum Audibility: Equatable, Sendable {
    /// 還沒走到 flush 的裁決那一步。待發區裡的一律是這個。
    ///
    /// ⚠️ **待發區裡的事件必須維持 `.undecided`。** `NotificationEvent` 是
    /// `Equatable`，而 `pending.contains(where:)` 有三個呼叫點靠它擋重複入列；
    /// 在入列時就蓋旗標的話，那三道防護會**安靜地**改變行為。
    case undecided
    case audible
    case silent(Reason)

    public enum Reason: Equatable, Sendable {
        /// 失敗的那批不出聲。T2 刻意沒有文字，只有圖示與聲音 ——
        /// 所以「措辭要是失敗不是完成」這條承諾只剩聲音的有無可以兌現。
        /// 對一個失敗的 run 播同樣的聲音就是說謊，而且是那種你會信的謊。
        case failedOutcome
        /// 人不在。見 `Presence.worthSounding`。
        case noOneWatching
        /// 這一小時的額度用完了。見 `SoundBudget`。
        case budgetSpent
    }
}

public enum BatchOutcome: Equatable, Sendable {
    case completed
    /// run 自己回報失敗。措辭必須是失敗，不可以說「全部完成」。
    case failed
}

public struct BatchAlert: Equatable, Sendable {
    public let sessionId: String
    public let workflowId: String
    /// 這個 run 的**最後一個**階段。T2 送出時 run 一定已經終結
    /// （`NotificationEngine` 的 `terminated` 是前提），所以 journal 不會再長。
    /// nil ＝ journal 讀不到，見 `WorkflowJournal.latestPhase`。
    public let latestPhase: String?
    public let total: Int
    public let outcome: BatchOutcome
    /// 這批**跑了多久**（秒），由 run 自己回報。見 `WorkflowRunState.duration`。
    ///
    /// ⚠️ nil ＝ run 狀態檔裡沒有 `durationMs`。那**不擋通知** ——
    /// `status` 是排空的正面證據，`duration` 只是附屬資訊，
    /// 拿一整則「7 個 agent 跑完了」去換一個沒填的秒數欄位是把
    /// 「寧可少報」用在錯的地方。
    public let runDuration: TimeInterval?
    /// 出不出聲，以及為什麼。由 `NotificationEngine.flush` 在送出前裁決。
    public let audibility: Audibility

    /// ⚠️ `audibility` **不給預設值**。全 repo 只有一個建構點
    /// （`NotificationEngine.observeBatches`），而不給預設值買到的是：
    /// 將來多開一條產生 T2 的路徑時，漏掉裁決是編譯錯誤而不是靜音的預設。
    public init(sessionId: String, workflowId: String, latestPhase: String?, total: Int,
                outcome: BatchOutcome, runDuration: TimeInterval?, audibility: Audibility) {
        self.sessionId = sessionId
        self.workflowId = workflowId
        self.latestPhase = latestPhase
        self.total = total
        self.outcome = outcome
        self.runDuration = runDuration
        self.audibility = audibility
    }

    /// 裁決之後換上旗標的那一份。
    public func with(audibility: Audibility) -> BatchAlert {
        BatchAlert(sessionId: sessionId, workflowId: workflowId, latestPhase: latestPhase,
                   total: total, outcome: outcome, runDuration: runDuration,
                   audibility: audibility)
    }
}

// ── T3 ────────────────────────────────────────────────────────

public struct QuotaTierAlert: Equatable, Sendable {
    public let from: QuotaTier
    public let to: QuotaTier

    public init(from: QuotaTier, to: QuotaTier) {
        self.from = from
        self.to = to
    }
}
