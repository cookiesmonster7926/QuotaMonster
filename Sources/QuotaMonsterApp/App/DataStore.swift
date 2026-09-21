import Foundation
import Observation
import QuotaMonsterCore

/// 應用程式的單一資料來源。
///
/// **零 token、零行程、零網路。** 全部是讀既有的檔案：
/// 額度有兩個來源（見下），session 來自 `~/.claude/sessions/`，agent 樹來自
/// `~/.claude/projects/<slug>/<sessionId>/subagents/`。
///
/// 額度的兩個來源：
///   1. `~/.claude.json` 的 `cachedUsageUtilization` —— Claude Code 自己維護，
///      但實測可以整整 16 小時不更新，而且已經重置的窗口還留在裡面
///   2. statusline tee 的快取 —— 跟著 API 回應走，秒級，而且是**唯一**
///      拿得到每個 session 的 context 壓力的地方
///
/// 兩者由 `UsageSourceSelector` 挑一個，**不做欄位層級的合併**（理由見該型別）。
@MainActor
@Observable
final class DataStore {

    private(set) var usage: UsageSnapshot?
    /// 這筆 `usage` 是從哪裡來的。UI 要據此說明它為什麼新、或為什麼舊。
    private(set) var usageSource: UsageSource?
    /// sessionId → 該 session 最後一次 statusLine payload。context 壓力從這裡來。
    private(set) var statusLine: [String: StatusLinePayload] = [:]
    /// 分模型的 7 天用量，**連同它自己的擷取時間**。
    ///
    /// 這份只有 `~/.claude.json` 有（statusLine payload 沒有這個欄位），
    /// 所以它的新鮮度與上面那個 `usage` 是分開的 —— 面板一定要標出年齡。
    private(set) var scoped: ScopedBreakdown?
    /// 快取目錄裡總共讀到幾份 payload（含沒有 session_id 的 _unkeyed）。
    ///
    /// UI 需要這個數字才分得出兩種完全不同的狀況：**沒裝 tee**，
    /// 以及**tee 有在寫、但那些 payload 剛好都沒有帶額度窗口**
    /// （例如 session 還沒發出第一個 API 呼叫）。少了它，面板會在 tee 明明
    /// 一秒前才寫過檔的時候說「沒裝 statusline tee」。
    private(set) var statusLinePayloadCount = 0
    private(set) var sessions: [LiveSession] = []
    private(set) var trees: [String: AgentTree] = [:]      // sessionId → tree
    /// sessionId → 它剛剛講完的那一輪。見 `SessionFinish`。
    private(set) var finishes: [String: SessionFinish] = [:]
    private(set) var lastRefresh = Date.distantPast
    /// 使用者調過的那幾格。沒調過的欄位是 nil，見 `Preferences`。
    private(set) var preferences = Preferences.empty

    /// 額度分級的邊界 —— 解析一次，三個消費者（圖示、面板、T3）共用。
    ///
    /// ⚠️ 這個 computed property 是規矩 2 在這個功能上的執行手段：
    /// `?? .standard` 只出現在這裡一次，所有消費者都經過它。
    var quotaThresholds: QuotaThresholds {
        guard let c = preferences.quotaCritical, let t = preferences.quotaTight else {
            return .standard
        }
        return QuotaThresholds(critical: c, tight: t)
    }

    var runningAgents: Int { trees.values.reduce(0) { $0 + $1.runningAgentCount } }
    var summary: SessionSummary { SessionSummary(sessions) }
    var glyph: GlyphState {
        GlyphState.from(usage: usage, sessions: sessions, runningAgents: runningAgents,
                        thresholds: quotaThresholds)
            // ⚠️ `now` 用 `lastRefresh` 而不是 `Date()` —— 面板那一列也用它，
            // 兩邊必須對著同一個「現在」，否則鮮度線與選單列會各自衰退。
            .with(finishGlow: FinishGlow.menuBar(Array(finishes.values), now: lastRefresh))
    }

    private let home = FileManager.default.homeDirectoryForCurrentUser
    private let usageReader = ClaudeJSONUsageReader()
    private let statusLineReader = StatusLineCacheReader()
    private let pruner = StatusLineCachePruner()
    private let history = UsageHistory()
    private let registry = SessionRegistryReader()
    /// 通知的決策層。`var` 因為 `update` 是 mutating。
    private var notifier = NotificationEngine()
    /// 送出去的那一端。App 層注入，Core 完全不知道它存在。
    private var presenter: NotificationPresenting?
    private let resolver = SessionDirectoryResolver()
    private let treeBuilder = AgentTreeBuilder()
    private let completionReader = TurnCompletionReader()
    /// 沉澱窗狀態機。I/O 三支注入，所以它本身是純的、測得到。
    @ObservationIgnored private lazy var completionTracker = CompletionTracker(
        readTail: { [r = completionReader] in r.read($0) },
        readTurnStart: { [r = completionReader] in r.readTurnStart($0) },
        modifiedAt: { [r = completionReader] in r.modifiedAt($0) })
    /// sessionId → transcript。
    ///
    /// ⚠️ **一定要快取。** `resolver.transcript` 會列舉整個 projects 目錄，
    /// 而下面建 agent 樹的 `locate()` 每個 session 每 3 秒已經列舉過一次了 ——
    /// 不快取就是把那個成本再翻一倍。
    private var transcriptPaths: [String: URL] = [:]
    private var timer: Timer?
    private var lastPrune = Date.distantPast
    /// 歷史檔自己的清理節奏，與 statusline 快取分開。理由見 `UsageHistory.pruneInterval`。
    private var lastHistoryPrune = Date.distantPast
    /// 最後一次寫進時間序列的取樣點。留在記憶體裡，才不必每 3 秒讀一次整個歷史檔。
    /// 開機時由 `start()` 從檔案讀回來，否則每次重啟都會再寫一筆一樣的。
    private var lastRecorded: UsageSample?
    /// 最近 24 小時的取樣點，給燒量估計用。
    ///
    /// ⚠️ **在 `refresh()` 裡種，不是在 `start()`。** `RenderPanel` 只建 DataStore
    /// 然後呼叫 `refresh()`，從來不呼叫 `start()` —— 種在 start 裡的話，
    /// 診斷指令畫出來的面板永遠沒有箭頭，而那正是要用它檢查的東西。
    private(set) var recentSamples: [UsageSample] = []
    private var samplesSeeded = false
    /// 只有真的在跑的 app 會寫時間序列。
    ///
    /// `--dump` / `--render-panel` 這些診斷指令也會建 DataStore 並呼叫 refresh()，
    /// 讓它們寫檔的話，光是跑幾次診斷就會在歷史裡塞進一堆重複的點。
    private var recordsHistory = false
    /// 通知也一樣只有真的在跑的 app 會發。
    ///
    /// `refresh()` 有六個呼叫點，包括 `--dump` 與 `--render-panel` ——
    /// 不擋的話，跑一次診斷指令就會浮出一排警示視窗。
    private var deliversNotifications = false
    /// 完成偵測也一樣只有真的在跑的 app 會做。
    ///
    /// 與 `recordsHistory` / `deliversNotifications` 同一條規矩：`refresh()` 有六個
    /// 呼叫點，包括 `--dump` 與 `--render-panel`。不擋的話，跑一次診斷指令就會
    /// 讀一輪 transcript 尾端，而那正是這個設計最想避免的成本。
    private var detectsCompletions = false

    /// tee 寫出來的快取目錄。路徑常數在 Core，與 shell wrapper 有測試對帳。
    private var statusLineCache: URL { StatusLineCacheReader.defaultDirectory(home: home) }
    private var historyFile: URL { UsageHistory.defaultURL(home: home) }
    private var notifyStateFile: URL { NotifyState.defaultURL(home: home) }
    private var preferencesFile: URL { Preferences.defaultURL(home: home) }

    /// 清理的間隔。刪檔比讀檔貴得多，而且垃圾累積得很慢
    /// （只有 SIGKILL 才會留下孤兒），沒必要跟著 3 秒的輪詢一起做。
    static let pruneInterval: TimeInterval = 60

    /// 慢輪詢。FSEvents 監看是 V2 的事；先用固定間隔把功能跑通。
    /// 全部是 stat + 小檔案解析，成本可以忽略。
    static let refreshInterval: TimeInterval = 3

    /// 記憶體裡留多久的取樣點。燒量估計最多只看回一個 5 小時窗口，
    /// 24 小時已經是很寬的餘裕，而且它讓整份歷史不必每三秒讀一次。
    static let sampleWindow: TimeInterval = 24 * 3600

    func start() {
        // 偏好要**最早**讀 —— 音效的選擇在第一次通知之前就要生效。
        if let saved = Preferences.load(preferencesFile) { preferences = saved }
        applyPreferences()
        // 先把上一筆讀回來，重啟才不會又寫一次一模一樣的紀錄。
        lastRecorded = history.last(historyFile)
        // 靜音是使用者直接下的指令，時間跨度（「到明早」約 12 小時）遠長於
        // 這個 app 的一次執行。不讀回來 = 在他明確要求安靜的時段裡出聲。
        if let saved = NotifyState.load(notifyStateFile) {
            notifier.restore(mutedUntil: saved.mutedUntil)
        }
        recordsHistory = true
        deliversNotifications = true
        detectsCompletions = true
        refresh()
        let t = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        // .common 模式，才不會在選單追蹤時停住。
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() { timer?.invalidate(); timer = nil }

    func attach(presenter: NotificationPresenting) { self.presenter = presenter }

    /// 只給 `--render-panel --demo-finish` 用：塞一筆**合成的**完成標記。
    ///
    /// 為什麼需要它：完成訊號一天只出現幾次，而「畫面上沒有那一列」**不是**
    /// 「那個版面不成立」的證據。靠等一個真的剛完成的 session 來驗收版面，
    /// 等於把驗收交給運氣。
    /// ⚠️ 診斷輸出必須講明那一列是合成的。
    func seedSyntheticFinish(_ finish: SessionFinish) { finishes[finish.sessionId] = finish }

    // ── 靜音 ───────────────────────────────────────────────────

    var mutedUntil: Date? { notifier.mutedUntil }
    var isMuted: Bool { notifier.isMuted(at: Date()) }

    /// nil 代表解除。循環的順序由 `MutePolicy.next` 決定。
    func setMute(_ until: Date?) {
        if let until { notifier.mute(until: until) } else { notifier.unmute() }
        persistNotifyState()
    }

    // ── 偏好 ───────────────────────────────────────────────────

    func setPreferences(_ p: Preferences) {
        preferences = p.sanitised()
        Preferences.save(preferences, to: preferencesFile)
        applyPreferences()
    }

    /// 把偏好推到那些「不是每次繪製都會去問」的地方。
    ///
    /// 今天只有音效一項 —— 其餘（「明早」幾點、ctx 門檻）都是在用到的那一刻
    /// 以 `?? 預設` 解析，所以不需要推。
    private func applyPreferences() {
        AlertSound.choice = preferences.alertSound ?? .named(AlertSound.defaultName)
    }

    private func persistNotifyState() {
        NotifyState.save(NotifyState(mutedUntil: notifier.mutedUntil), to: notifyStateFile)
    }

    func refresh() {
        let now = Date()

        // 過期的窗口在這裡就會被丟掉，所以「有值」一律代表「還在這個窗口裡」。
        let payloads = statusLineReader.read(directory: statusLineCache, now: now)
        statusLinePayloadCount = payloads.count
        statusLine = Dictionary(payloads.compactMap { p in p.sessionId.map { ($0, p) } },
                                uniquingKeysWith: { $1.capturedAt > $0.capturedAt ? $1 : $0 })

        let claudeJSON = home.appendingPathComponent(".claude.json")
        let fromClaudeJSON = try? usageReader.read(claudeJSON, now: now, expectedAccount: nil)
        scoped = try? usageReader.readScoped(claudeJSON, now: now)
        let picked = UsageSourceSelector.pick(claudeJSON: fromClaudeJSON,
                                              statusLine: payloads, now: now)
        usage = picked?.snapshot
        usageSource = picked?.source

        // 時間序列：磁碟上沒有別的地方記錄額度隨時間的變化，長條圖與燒量速率
        // 都要靠自己累積。數字沒變就不寫 —— 三秒輪詢一天會問兩萬多次。
        if !samplesSeeded {
            samplesSeeded = true
            recentSamples = history.read(historyFile, now: now)
                .filter { now.timeIntervalSince($0.at) <= Self.sampleWindow }
        }

        if recordsHistory,
           let sample = UsageSample(usage, at: now),
           UsageHistory.shouldRecord(sample, previous: lastRecorded) {
            if history.append(sample, to: historyFile) {
                lastRecorded = sample
                recentSamples.append(sample)
            }
        }

        if now.timeIntervalSince(lastPrune) > Self.pruneInterval {
            pruner.prune(directory: statusLineCache, now: now)
            lastPrune = now
        }
        if now.timeIntervalSince(lastHistoryPrune) > UsageHistory.pruneInterval {
            history.prune(historyFile, now: now)
            recentSamples.removeAll { now.timeIntervalSince($0.at) > Self.sampleWindow }
            lastHistoryPrune = now
        }

        let raw = registry.read(directory: home.appendingPathComponent(".claude/sessions"))
        sessions = SessionStateResolver().resolve(raw)

        let projects = home.appendingPathComponent(".claude/projects")
        var built: [String: AgentTree] = [:]
        for s in sessions {
            guard let paths = resolver.locate(sessionId: s.session.sessionId,
                                              projectsRoot: projects) else { continue }
            built[s.session.sessionId] = treeBuilder.build(
                paths: paths, sessionId: s.session.sessionId,
                sessionStartedAt: s.session.startedAt)
        }
        trees = built

        // 完成偵測。**在通知之前**，因為選單列的 glyph 要讀 `finishes`。
        if detectsCompletions {
            var transcripts: [String: URL] = [:]
            for s in sessions {
                let id = s.session.sessionId
                if let cached = transcriptPaths[id] {
                    transcripts[id] = cached
                    continue
                }
                // ⚠️ 不可以用 `resolver.locate()` —— 它硬性要求 `<sessionId>/` 目錄存在，
                // 而〔實測〕40 個 transcript 只有 15 個有那個兄弟目錄。
                guard let url = resolver.transcript(sessionId: id, projectsRoot: projects)
                else { continue }
                transcriptPaths[id] = url
                transcripts[id] = url
            }
            let alive = Set(sessions.map(\.session.sessionId))
            transcriptPaths = transcriptPaths.filter { alive.contains($0.key) }

            let out = completionTracker.update(CompletionInput(transcripts: transcripts), now: now)
            for f in out.finishes { finishes[f.sessionId] = f }
            // ⚠️ 「又動起來了」的證據是 **transcript 的 mtime 前進**，不是
            // `session.isWorking` —— 註冊表的 status 是黏著的（回合結束後七分鐘
            // 一直回報 shell），拿它當證據的話標記會在產生後的第一拍就被清掉。
            finishes = FinishCaption.prune(finishes, wrote: out.wrote, now: now)
        }

        // 通知在這裡驅動：這是這一拍裡 usage / sessions / trees 全部一致的第一個點。
        if deliversNotifications {
            let input = NotificationInput(sessions: sessions, trees: trees, usage: usage,
                                          presence: ScreenPresence.snapshot())
            notifier.update(input, now: now)
            for event in notifier.flush(now: now) { presenter?.present(event) }
            // 已經不在等的，浮窗要立刻收掉。
            presenter?.resolve(stillWaiting: Set(sessions.filter(\.needsHuman)
                                                         .map(\.session.sessionId)))
        }

        lastRefresh = now
    }
}
