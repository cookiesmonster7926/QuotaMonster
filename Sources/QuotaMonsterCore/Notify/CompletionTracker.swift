import Foundation

/// 餵給沉澱窗的一拍：sessionId → 它的 transcript，以及這一拍往前掃到的回合起點。
public struct CompletionInput: Equatable, Sendable {
    public let transcripts: [String: URL]
    /// sessionId → 這一輪是誰開的（`TranscriptWatcher.opening(of:)`）。
    /// ⚠️ **沒有這個 key ＝ 整個沒看到**（watcher 沒讀到過那份 transcript），
    /// 與 `.noHumanYet`（讀到了、沒有真人訊息）是兩件事。兩者的 `ranFor` 都是 nil，
    /// 但診斷要分得開（規矩 28）。
    public let openings: [String: TurnOpener.Answer]
    public init(transcripts: [String: URL], openings: [String: TurnOpener.Answer] = [:]) {
        self.transcripts = transcripts
        self.openings = openings
    }
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
/// 純狀態機，零 `Date()`、零計時器。I/O 兩支當 closure 注入
/// （形狀抄 `SessionStateResolver(isAlive:)`）；回合起點是**資料**，由呼叫端
/// 從往前掃的 `TranscriptWatcher` 帶進來（`CompletionInput.openings`）。
public struct CompletionTracker: Sendable {

    /// 連續多久沒有寫入才去讀尾端。
    ///
    /// ⚠️ **不可以往下砍。**〔實測 n=153〕兩行式 end_turn（thinking 然後 text）的
    /// 間隔最大 **51.8 秒** —— 窗縮到 45 秒就會在 thinking 那一行到期，
    /// 而此時 `stop_reason` 已經是 `end_turn`：選單列亮起丁香紫、面板寫「剛完成」，
    /// 而使用者眼前**還沒有任何文字**。
    /// 〔實測，現場直接觀測〕一個跑到一半的 session 最長安靜 83.9 秒，離 90 只剩 6 秒。
    public static let settleWindow: TimeInterval = 90

    struct Watch: Equatable, Sendable {
        var lastModified: Date
        var quietSince: Date
        var confirmedQuiet: Bool
        /// 這一次安靜已經讀過尾端了。一次安靜只讀一次。
        var readThisQuiet: Bool
        /// 我們**第一次看到這個 session** 的時刻。跨重啟的守門靠它。
        let firstSeenAt: Date
        var lastAnnounced: Date?
    }

    private var watches: [String: Watch] = [:]
    private let readTail: @Sendable (URL) -> TurnReadout
    private let modifiedAt: @Sendable (URL) -> Date?

    public init(readTail: @escaping @Sendable (URL) -> TurnReadout,
                modifiedAt: @escaping @Sendable (URL) -> Date?) {
        self.readTail = readTail
        self.modifiedAt = modifiedAt
    }

    /// `ranFor` 算不出來的原因。**全 repo 只有這一份**：正式路徑（`ranFor`）、
    /// `--measure-ranfor`（`RanForCoverage`）與 `--trace-finishes` 都從 `ranForOutcome` 拿，
    /// 這裡多一個 nil 的條件，三邊一起看得到，不會有一邊印出舊的原因。
    public enum RanForMiss: String, CaseIterable, Sendable {
        /// 整個沒看到：watcher 沒讀到過這份 transcript（`openings` 沒有這個 key）。
        case unseen
        /// 看到了，但這一輪不是人開的（`.wokenWithoutHuman`）。
        case woken
        /// 看到了，一則真人訊息都沒有（`.noHumanYet`）。
        case noHuman
        /// 最後一則真人訊息沒帶時刻（`.humanWithoutTimestamp`）。
        case noTimestamp
        /// 起點不早於完成時刻 —— 時間戳不單調〔實測〕3.91% 的相鄰行對為負。
        case notAfterStart
    }

    public enum RanForOutcome: Equatable, Sendable {
        case ran(TimeInterval)
        case missing(RanForMiss)
    }

    /// 這一輪跑了多久，或者為什麼算不出來。只有「真人開的、有時刻、而且早於完成」才算得出來。
    ///
    /// ⚠️ 舊作法還有一道 15 秒的容忍度（`turnStartTolerance`），擋的是「寬鬆的起點定義」
    /// 〔實測，模擬〕p90 = 5,192 秒、max = 69,812 秒。那個寬鬆來自**跨過上一輪**去找起點；
    /// 現在「最後一則真人訊息之後模型停下來過（講完或被中斷）又動起來」本身就是
    /// `.wokenWithoutHuman`，所以不再需要一個選出來的數字去猜「這個起點是不是太舊」——
    /// 很長的回合就是很長。⚠️ 這個前提**全靠 `TurnOpener` 認得出「停下來過」**：
    /// 它漏認一種停下的方式，這裡就會把閒置算進來，而且沒有上限擋著。
    public static func ranForOutcome(opening: TurnOpener.Answer?, finishedAt: Date) -> RanForOutcome {
        switch opening {
        case nil:                          return .missing(.unseen)
        case .wokenWithoutHuman?:          return .missing(.woken)
        case .noHumanYet?:                 return .missing(.noHuman)
        case .humanWithoutTimestamp?:      return .missing(.noTimestamp)
        case .human(let start)?:
            return finishedAt > start ? .ran(finishedAt.timeIntervalSince(start)) : .missing(.notAfterStart)
        }
    }

    /// `ranForOutcome` 的投影：算得出來的秒數，否則 nil（「不知道」，不是 0）。
    public static func ranFor(opening: TurnOpener.Answer?, finishedAt: Date) -> TimeInterval? {
        guard case .ran(let r) = ranForOutcome(opening: opening, finishedAt: finishedAt) else { return nil }
        return r
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
                                    firstSeenAt: now, lastAnnounced: nil)
                continue
            }

            if mtime != watch.lastModified {
                // 又動起來了。⚠️ 這裡**不再**順便讀回合起點：舊作法只在「確認安靜之後
                // 又動起來」那一刻往 64KB 尾端搆，回得快的人與長回合都搆不到
                // （第三節第 33 條：7/7 算不出來）。起點改由往前掃的游標提供。
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
                    let ranFor = Self.ranFor(opening: input.openings[id], finishedAt: end.finishedAt)
                    finishes.append(SessionFinish(sessionId: id,
                                                  finishedAt: end.finishedAt, ranFor: ranFor))
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
