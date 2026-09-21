import Foundation

/// 餵給沉澱窗的一拍：sessionId → 它的 transcript。
public struct CompletionInput: Equatable, Sendable {
    public let transcripts: [String: URL]
    public init(transcripts: [String: URL]) { self.transcripts = transcripts }
}

/// 「哪個 session 剛剛講完了一輪。」
///
/// ### 沉澱窗**不是**偵測
/// 計畫書寫「沉澱窗本身就是偵測」，那句話會誤導實作。
/// 安靜只決定**何時去看**，決定**完成沒**的是尾端那一則的 `stop_reason`。
/// 這個分工正是整個方案的救命符：〔實測〕13,733 個回合進行中的間隔裡有 105 個
/// （0.76%）超過 90 秒（長 Bash 66.7%、模型自己想很久 20.0%、使用者在打字 11.4%），
/// 但那些時點往回看到的全部是 `tool_use` —— **誤報 0 次**。
/// 一個跑 40 分鐘的 Bash 在架構上就不可能誤觸發，它只會多花一次 37µs 的讀取。
///
/// ### 形狀
/// 純狀態機，零 `Date()`、零計時器。I/O 三支全部當 closure 注入
/// （形狀抄 `SessionStateResolver(isAlive:)`）。
public struct CompletionTracker: Sendable {

    /// 連續多久沒有寫入才去讀尾端。
    ///
    /// ⚠️ **不可以往下砍。**〔實測 n=153〕兩行式 end_turn（thinking 然後 text）的
    /// 間隔最大 **51.8 秒** —— 窗縮到 45 秒就會在 thinking 那一行到期，
    /// 而此時 `stop_reason` 已經是 `end_turn`：選單列亮起丁香紫、面板寫「剛完成」，
    /// 而使用者眼前**還沒有任何文字**。
    /// 〔實測，現場直接觀測〕一個跑到一半的 session 最長安靜 83.9 秒，離 90 只剩 6 秒。
    public static let settleWindow: TimeInterval = 90

    /// 「安靜 → 又動起來」那一刻讀到的回合起點，比現在早超過這麼多就丟掉。
    ///
    /// ⚠️ **這個數字是選的，沒有資料能決定它。** 但沒有它的後果量得出來：
    /// 用寬鬆的起點定義模擬出來的 `ranFor` p90 = 5,192 秒、max = 69,812 秒
    /// （19.4 小時）〔實測，模擬〕—— 面板會定期顯示「跑了 19h 23m」。
    public static let turnStartTolerance: TimeInterval = 15

    struct Watch: Equatable, Sendable {
        var lastModified: Date
        var quietSince: Date
        var confirmedQuiet: Bool
        /// 這一次安靜已經讀過尾端了。一次安靜只讀一次。
        var readThisQuiet: Bool
        /// 我們**第一次看到這個 session** 的時刻。跨重啟的守門靠它。
        let firstSeenAt: Date
        var turnStart: Date?
        var lastAnnounced: Date?
    }

    private var watches: [String: Watch] = [:]
    private let readTail: @Sendable (URL) -> TurnReadout
    private let readTurnStart: @Sendable (URL) -> Date?
    private let modifiedAt: @Sendable (URL) -> Date?

    public init(readTail: @escaping @Sendable (URL) -> TurnReadout,
                readTurnStart: @escaping @Sendable (URL) -> Date?,
                modifiedAt: @escaping @Sendable (URL) -> Date?) {
        self.readTail = readTail
        self.readTurnStart = readTurnStart
        self.modifiedAt = modifiedAt
    }

    /// - Returns: 這一拍新產生的完成標記，以及**哪些 session 的 transcript 又被寫了**
    ///   （呼叫端據此收掉舊標記 —— 見 `FinishCaption.prune`）。
    public mutating func update(_ input: CompletionInput,
                                now: Date) -> (finishes: [SessionFinish], wrote: Set<String>) {
        var finishes: [SessionFinish] = []
        var wrote: Set<String> = []

        for (id, url) in input.transcripts {
            // ⚠️ **stat 失敗不是「它安靜了」。** 把 nil 當成安靜的實作會在檔案
            // 暫時讀不到的時候憑空宣告完成。
            guard let mtime = modifiedAt(url) else { continue }

            guard var watch = watches[id] else {
                // 第一次看到：只記錄，不讀不發。我們沒有見證它完成。
                watches[id] = Watch(lastModified: mtime, quietSince: now,
                                    confirmedQuiet: false, readThisQuiet: false,
                                    firstSeenAt: now, turnStart: nil, lastAnnounced: nil)
                continue
            }

            if mtime != watch.lastModified {
                // 又動起來了。**從安靜轉為活躍的那一刻**才去問這一輪從哪裡開始 ——
                // 計畫書那個「從 64KB 尾端回推到回合起點」做不到（〔實測〕整個回合
                // 塞得進 64KB 的只有 37.4%）。
                if watch.confirmedQuiet, watch.turnStart == nil,
                   let candidate = readTurnStart(url),
                   now.timeIntervalSince(candidate) <= Self.turnStartTolerance {
                    watch.turnStart = candidate
                }
                watch.lastModified = mtime
                watch.quietSince = now
                watch.confirmedQuiet = false
                watch.readThisQuiet = false
                wrote.insert(id)
                watches[id] = watch
                continue
            }

            guard now.timeIntervalSince(watch.quietSince) >= Self.settleWindow else {
                watches[id] = watch
                continue
            }
            watch.confirmedQuiet = true
            // 一次安靜只讀一次尾端。三個 session 一天讀幾十次，不是每三秒。
            guard !watch.readThisQuiet else { watches[id] = watch; continue }
            watch.readThisQuiet = true

            if case .finished(let end) = readTail(url) {
                // ⚠️ **在我們看到它之前就完成的那一輪不發。**
                // 用「有沒有寫過」當布林閂鎖是不夠的：一個 120 秒前完成的 session，
                // 重啟後只要 harness 寫一行就過關，而壽命上限也攔不住。
                // 時間比較一道就擋掉兩種，而且天生沒有「閂鎖忘了重新武裝」那種洞。
                let witnessed = end.finishedAt >= watch.firstSeenAt
                let isNew = end.finishedAt != watch.lastAnnounced
                let stillNews = now.timeIntervalSince(end.finishedAt) <= FinishGlow.goneSeconds

                if witnessed, isNew, stillNews {
                    // `>` 那個判斷擋的是時間戳不單調〔實測〕3.91% 的相鄰行對為負。
                    let ranFor = watch.turnStart.flatMap {
                        end.finishedAt > $0 ? end.finishedAt.timeIntervalSince($0) : nil
                    }
                    finishes.append(SessionFinish(sessionId: id,
                                                  finishedAt: end.finishedAt, ranFor: ranFor))
                    watch.turnStart = nil
                }
                // 記下來就不會每次沉澱都重判同一則。**去重靠身分（finishedAt），
                // 不靠時間窗** —— 兩行式 end_turn 的間隔中位 12.2 秒、最大 51.8 秒，
                // 任何時間窗門檻都會給出不同答案。
                watch.lastAnnounced = end.finishedAt
            }
            watches[id] = watch
        }

        // session 不在了，watch 跟著收。它回來時 firstSeenAt 會重設，
        // 而那正是我們要的：重新開始見證。
        watches = watches.filter { input.transcripts[$0.key] != nil }
        return (finishes, wrote)
    }
}
