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

    /// 「那一天沒用量」與「那一天我們沒在看」分得開，靠的是它。
    /// ⚠️ 刻意寫在**另一個檔案**，`usage-history.jsonl` 的語意一個字都不動 ——
    /// 理由（以及這一步為什麼曾經被擱置）見 `WatchLog` 的檔頭。
    private let watchLog = WatchLog()
    private var lastWatchMark: Date?
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

    /// 這一列該顯示的名字。
    ///
    /// 註冊表的 `name` 在 `nameSource == "derived"` 時是 Claude Code 從 cwd 湊的
    /// 佔位名（`rl-1b`、`usage-ff`）——**使用者從來沒有看過它**。
    /// 他真正看到的（VS Code 分頁上的 `0922作業`、終端機的 `修t2`）在 transcript 裡。
    ///
    /// ⚠️ 還要處理**同名**：〔實測 2026-09-22〕5 個存活 session 裡 4 個同名
    /// （fork／resume 沿用同一個 `aiTitle`）。判準全部在 `SessionTitle`（Core）。
    func displayName(for session: ClaudeSession) -> String {
        resolvedNames[session.sessionId] ?? rawTitle(for: session)
    }

    /// 這一輪所有存活 session 的顯示名，同名的已經接上唯一鍵。
    /// ⚠️ 必須一次算完整批 —— 「同名」是**整批**的性質，一個一個算看不出來。
    private var resolvedNames: [String: String] {
        SessionTitle.disambiguate(sessions.map {
            SessionTitle.Titled(id: $0.session.sessionId,
                                title: rawTitle(for: $0.session),
                                uniqueKey: $0.session.name)
        })
    }

    private func rawTitle(for session: ClaudeSession) -> String {
        let fallback = session.name ?? String(session.sessionId.prefix(8))
        guard SessionTitle.isPlaceholder(session.nameSource) else { return fallback }
        return SessionTitle.display(name: session.name, nameSource: session.nameSource,
                                    transcriptTitle: { cachedTitle(for: session.sessionId) })
            ?? fallback
    }

    private func cachedTitle(for sessionId: String) -> String? {
        let now = Date()
        if let hit = titles[sessionId],
           now.timeIntervalSince(hit.at) < SessionTitle.refreshInterval {
            return hit.title
        }
        // 優先用 transcriptPaths 這個既有的快取 —— resolver.transcript 會列舉
        // 整個 projects 目錄，重算一次等於把那個成本再翻一倍。
        //
        // ⚠️ **但不可以只靠它。** 它是在 `if detectsCompletions` 裡面被填的，
        // 而那個旗標只有真的 `start()` 之後才是 true ——`--render-panel` 這條路
        // 不會走到，於是診斷會畫出一張名字與真實面板**不一樣**的圖（規矩 28）。
        // 快取沒有就自己解析一次，結果（含 nil）快取 60 秒，不會反覆列舉。
        let url = transcriptPaths[sessionId] ?? {
            let u = resolver.transcript(
                sessionId: sessionId,
                projectsRoot: home.appendingPathComponent(".claude/projects"))
            if let u { transcriptPaths[sessionId] = u }
            return u
        }()
        let title = url.flatMap { SessionTitle.aiTitle(inTranscript: $0) }
        titles[sessionId] = (title, now)
        return title
    }

    /// sessionId → （顯示名, 什麼時候撈的）。
    ///
    /// ⚠️ 只有 `nameSource == "derived"` 的 session 會進來（見 `SessionTitle`），
    /// 而且每 `SessionTitle.refreshInterval` 秒才重撈一次。
    private var titles: [String: (title: String?, at: Date)] = [:]
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

    /// 每日長條圖要的那一份。
    ///
    /// ⚠️ **不可以把 `sampleWindow` 從 24 小時放大到 7 天** —— 那個常數餵的是
    /// `UsageBurn` 的分段迴歸，放大它會靜靜地改掉燒量速率看到的東西。
    /// 這裡另外留一份，多留一天當緩衝（窗口邊界附近要取得到「邊界當下的值」）。
    private(set) var weekSamples: [UsageSample] = []
    static let weekWindow: TimeInterval = 8 * 86400

    /// 心跳與開機標記。`DailyUsage` 靠它分辨「那天沒用」與「那天我們沒在看」。
    /// ⚠️ 開機時讀一次，之後只追加我們自己寫出去的那些 —— 這個檔案只有我們在寫。
    private(set) var watchMarks: [WatchLog.Mark] = []
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
    private var watchLogFile: URL { WatchLog.defaultURL(home: home) }

    /// 面板要印給使用者照做的那一行安裝指令。
    ///
    /// ⚠️〔code review 2026-09-22〕這裡原本寫死 repo 相對路徑
    /// `bash scripts/install_statusline_tee.sh --apply`，而**下載 DMG 的人沒有 repo** ——
    /// 新使用者唯一會看到的指引因此不可執行。`make_app.sh` 現在把 `scripts/`
    /// 打進 `Contents/Resources/`，這裡解析出絕對路徑。
    ///
    /// ⚠️ 純 CLI binary（`--render-panel` 那條路）沒有 bundle，
    /// 那時退回 repo 相對路徑 —— 在那個情境下它是對的。
    var installCommand: String {
        if let url = Bundle.main.resourceURL?
            .appendingPathComponent("scripts/install_statusline_tee.sh"),
           FileManager.default.isReadableFile(atPath: url.path) {
            // 路徑含空白（~/Applications/QuotaMonster.app 不會，但使用者可能改名），
            // 所以一定要引號。
            return "bash \"\(url.path)\" --apply"
        }
        return "bash scripts/install_statusline_tee.sh --apply"
    }

    /// 額度區塊底下要畫哪一種圖。判準與「為什麼這一格可以是旋鈕」見 `ChartStyle`。
    var chartStyle: ChartStyle { preferences.chartStyle ?? .standard }

    /// 累計曲線的點。⚠️ 與長條圖吃同一份 `weekSamples`，
    /// 兩張圖不可以各自撈一次資料 —— 那會變成兩份可能不一致的真相。
    var cumulativePoints: [DailyUsage.CumulativePoint]? {
        guard let resetsAt = usage?.sevenDay?.resetsAt else { return nil }
        return DailyUsage.cumulative(samples: weekSamples, resetsAt: resetsAt, now: lastRefresh)
    }

    /// 7 天窗口的起點與重置時刻。曲線要靠它們把時間映射到 x 軸。
    var quotaWindow: (start: Date, reset: Date)? {
        guard let reset = usage?.sevenDay?.resetsAt else { return nil }
        return (reset.addingTimeInterval(-Double(DailyUsage.days) * 86400), reset)
    }

    /// 每日長條圖的七根。⚠️ 判準全部在 `DailyUsage`（Core），這裡只餵資料。
    /// 沒有 7 天窗口的重置時間就畫不出來 —— 那不是「全部 0%」，是「沒有這張圖」。
    var dailyBars: [DailyUsageBar]? {
        guard let resetsAt = usage?.sevenDay?.resetsAt else { return nil }
        return DailyUsage.bars(samples: weekSamples, marks: watchMarks,
                               resetsAt: resetsAt, now: lastRefresh)
    }
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
        loadPreferences()
        // 先把上一筆讀回來，重啟才不會又寫一次一模一樣的紀錄。
        lastRecorded = history.last(historyFile)
        // 靜音是使用者直接下的指令，時間跨度（「到明早」約 12 小時）遠長於
        // 這個 app 的一次執行。不讀回來 = 在他明確要求安靜的時段裡出聲。
        if let saved = NotifyState.load(notifyStateFile) {
            notifier.restore(mutedUntil: saved.mutedUntil)
        }
        // ⚠️ 開機標記要在 `recordsHistory` 之前寫：它標的是「這裡是一次執行的起點」，
        // 而心跳的空隙**推不出**「重開了」還是「機器睡著了」—— 睡醒不會有 boot。
        // ⚠️ 開機標記**不是觀測證據**（sawLiveReading 留 false）——
        // 它只說「這裡是一次執行的起點」。
        watchLog.append(WatchLog.Mark(at: Date(), kind: .boot), to: watchLogFile)
        lastWatchMark = Date()
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

    /// 把磁碟上的偏好讀進來。`start()` 會呼叫，`--render-panel` 也會 ——
    ///
    /// ⚠️ 〔實測 2026-09-22〕在此之前**離線渲染完全看不到偏好**：`RenderPanel.run`
    /// 只呼叫 `refresh()`，而讀檔在 `start()` 裡。於是「改了偏好、渲染一張圖來看」
    /// 這個驗證動作，量到的一直是預設值 —— 它會在偏好真的壞掉時照樣給綠燈。
    /// 一個**只在真實 app 走的那條路上才讀設定**的診斷工具，等於沒有診斷。
    func loadPreferences() {
        if let saved = Preferences.load(preferencesFile) { preferences = saved }
        applyPreferences()
    }

    /// - Parameter persist: false 只改記憶體，**不寫檔**。
    ///   只有離線渲染（`--render-panel --chart …`）用得到 ——
    ///   一個診斷指令不可以改掉使用者真正的設定檔。
    func setPreferences(_ p: Preferences, persist: Bool = true) {
        preferences = p.sanitised()
        if persist { Preferences.save(preferences, to: preferencesFile) }
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
            // ⚠️ 只讀一次檔案，兩個視窗各自過濾 —— 讀兩次等於把成本翻倍。
            let all = history.read(historyFile, now: now)
            recentSamples = all.filter { now.timeIntervalSince($0.at) <= Self.sampleWindow }
            weekSamples = all.filter { now.timeIntervalSince($0.at) <= Self.weekWindow }
            watchMarks = watchLog.read(watchLogFile)
        }

        if recordsHistory,
           let sample = UsageSample(usage, at: now),
           UsageHistory.shouldRecord(sample, previous: lastRecorded) {
            if history.append(sample, to: historyFile) {
                lastRecorded = sample
                recentSamples.append(sample)
                weekSamples.append(sample)
            }
        }

        if now.timeIntervalSince(lastPrune) > Self.pruneInterval {
            pruner.prune(directory: statusLineCache, now: now)
            lastPrune = now
        }
        // 心跳。⚠️ 與歷史同一個閘（`recordsHistory`）—— 診斷指令不可以留下心跳，
        // 否則「那時 app 醒著」會被一支跑了兩秒就結束的 CLI 汙染。
        if recordsHistory, WatchLog.shouldWrite(lastWatchMark: lastWatchMark, now: now) {
            // ⚠️ 記的是「**那一刻看得到帳號的變化嗎**」，不是「app 醒著嗎」。
            // 只有讀數是 live 的時候，帳號層級的變化才會被我們及時看到。
            // 理由與代價見 `WatchLog.Mark.sawLiveReading`。
            let mark = WatchLog.Mark(at: now, kind: .heartbeat,
                                     sawLiveReading: usage?.freshness == .live)
            if watchLog.append(mark, to: watchLogFile) {
                lastWatchMark = now
                watchMarks.append(mark)
            }
        }

        if now.timeIntervalSince(lastHistoryPrune) > UsageHistory.pruneInterval {
            history.prune(historyFile, now: now)
            watchLog.prune(watchLogFile, now: now)
            recentSamples.removeAll { now.timeIntervalSince($0.at) > Self.sampleWindow }
            weekSamples.removeAll { now.timeIntervalSince($0.at) > Self.weekWindow }
            watchMarks.removeAll { now.timeIntervalSince($0.at) > WatchLog.retention }
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
                sessionStartedAt: s.session.startedAt, now: now)
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
            titles = titles.filter { alive.contains($0.key) }

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
