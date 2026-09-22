import AppKit
import QuotaMonsterCore

/// `--trace-alerts [秒數]` —— 用 Core 的同一套邏輯對著實時資料跑，把每一拍
/// 看到什麼、決定了什麼全部印出來。
///
/// **為什麼需要它：** 通知沒出現的時候，畫面上什麼線索都沒有 ——
/// 引擎沒發、發了被合併視窗吃掉、發了但 presenter 走了另一條通道，
/// 三者看起來一模一樣。`--demo-alert` 證明得了浮窗畫得出來，
/// 但證明不了「真的有事件走到它」。這支補上中間那一段。
@MainActor
enum TraceAlerts {

    /// ⚠️ 直接寫 fd 1，不用 `print`。
    ///
    /// Swift 的 `print` 在 stdout 不是 TTY 時是**區塊緩衝**的（4KB）——
    /// 導到檔案再去 tail，會看到一個空檔案，然後以為是追蹤器沒在跑。
    /// 這支工具的全部價值就是即時看得到，所以緩衝在這裡是致命的。
    static func say(_ line: String) {
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }

    static func run(seconds: Int) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let registry = SessionRegistryReader()
        let resolver = SessionDirectoryResolver()
        let builder = AgentTreeBuilder()
        let usageReader = ClaudeJSONUsageReader()
        let statusLineReader = StatusLineCacheReader()
        let history = UsageHistory()

        var engine = NotificationEngine()
        var lastStatuses: [String: String] = [:]
        var lastPresenceLine = ""
        var tick = 0

        say("追蹤 \(seconds) 秒 —— 每 3 秒一拍，只在有變化時印。")
        say("現在讓某個 session 進入等待狀態（問一個問題、或跑一個需要批准的工具）。")
        say(String(repeating: "─", count: 64))

        let deadline = Date().addingTimeInterval(TimeInterval(seconds))
        while Date() < deadline {
            let now = Date()
            tick += 1

            let payloads = statusLineReader.read(
                directory: StatusLineCacheReader.defaultDirectory(home: home), now: now)
            let claudeJSON = home.appendingPathComponent(".claude.json")
            let fromJSON = try? usageReader.read(claudeJSON, now: now, expectedAccount: nil)
            let usage = UsageSourceSelector.pick(claudeJSON: fromJSON, statusLine: payloads,
                                                 now: now)?.snapshot

            let raw = registry.read(directory: home.appendingPathComponent(".claude/sessions"))
            let sessions = SessionStateResolver().resolve(raw)

            var trees: [String: AgentTree] = [:]
            let projects = home.appendingPathComponent(".claude/projects")
            for s in sessions {
                guard let paths = resolver.locate(sessionId: s.session.sessionId,
                                                  projectsRoot: projects) else { continue }
                trees[s.session.sessionId] = builder.build(
                    paths: paths, sessionId: s.session.sessionId,
                    sessionStartedAt: s.session.startedAt, now: now)
            }

            // 狀態有變就印，這樣看得出「有沒有真的進入 waiting」。
            for s in sessions {
                let name = s.session.name ?? String(s.session.sessionId.prefix(8))
                let now = describe(s)
                if lastStatuses[name] != now {
                    say("[\(stamp())] 狀態  \(name.padding(toLength: 14, withPad: " ", startingAt: 0))"
                          + "\(lastStatuses[name] ?? "（第一次看到）") → \(now)")
                    lastStatuses[name] = now
                }
            }

            let samples = history.read(UsageHistory.defaultURL(home: home), now: now)
            _ = samples

            // ⚠️ 在場要**每一拍**印（有變化才印），不可以只印在事件迴圈裡。
            // 「為什麼那一聲沒響」正是這支工具存在的理由，而被閘擋掉的那些
            // 恰恰**不會**產生任何一行事件 —— 印在迴圈裡等於在最需要它的時候閉嘴。
            let presence = ScreenPresence.snapshot()
            let visible = ScreenPresence.canSeeAPanel
            // ⚠️ 判斷「有沒有變」的鍵**不含閒置秒數** —— 秒數每一拍都在變，
            // 拿它當鍵等於每拍都印，而「只在有變化時印」那句承諾就沒了，
            // 真正的狀態轉換也會淹死在裡面。秒數仍然印出來，只是不當鍵。
            let key = "\(presence.screenLocked)\(presence.screensAsleep)"
                + "\(presence.idleSeconds == nil)\(presence.worthSounding)\(visible)"
            if key != lastPresenceLine {
                say("[\(stamp())] 在場  鎖定 \(presence.screenLocked)"
                      + " 螢幕睡 \(presence.screensAsleep)"
                      + " 閒置 \(presence.idleSeconds.map { String(format: "%.0fs", $0) } ?? "讀不到")"
                      + " · 值得出聲嗎 \(presence.worthSounding)"
                      + " · 看得到浮窗嗎 \(visible)")
                lastPresenceLine = key
            }

            engine.update(NotificationInput(sessions: sessions, trees: trees, usage: usage,
                                            presence: presence),
                          now: now)
            for e in engine.flush(now: now) {
                say("[\(stamp())] ⚡️ 事件  \(describe(e))")
                say("             去重鍵 \(e.dedupKey)")
                // ⚠️ **這是影子值。** `--trace-alerts` 是獨立行程，上面那個
                // `var engine` 是它自己剛開機的引擎 —— 預算、everObservedIncomplete、
                // notified 全部都不是選單列上那個 app 的。在場那三個訊號是跨行程的
                // 機器狀態，印出來是真話；預算不是，所以一定要標死。
                if case .batchDrained = e {
                    say("             影子預算剩 \(engine.batchSoundBudgetRemaining(at: now))"
                          + "（這支追蹤器自己的，不是執行中那個 app 的）")
                }
            }

            Thread.sleep(forTimeInterval: DataStore.refreshInterval)
        }
        say(String(repeating: "─", count: 64))
        say("追蹤結束，共 \(tick) 拍。")
    }

    private static func describe(_ s: LiveSession) -> String {
        switch s.session.status {
        case .waiting(let r): return "waiting(\(r?.rawValue ?? "?"))"
        case .busy: return "busy"
        case .shell: return "shell"
        case .idle: return "idle"
        }
    }

    private static func describe(_ e: NotificationEvent) -> String {
        switch e {
        case .waiting(let a):
            return "T1 有人在等你 · \(a.sessions.map(\.project).joined(separator: ","))"
                + " · 合併=\(a.coalesced) 重推=\(a.isRepeat)"
        case .batchDrained(let b):
            // 音量的理由直接印 `audibility` 自己 —— **不要另外拼一個字串**：
            // 拼出來的那一份會在下一次改閘時默默說錯話。
            // ⚠️ `runDuration` 一定要有一個看得到的消費者。這個 repo 已經為
            // 「宣稱畫了卻沒畫」付過一次代價（`--render-alert` 說它畫了兩個在等，
            // 結果 n=2 的版面從來沒被眼睛看過）。
            return "T2 扇出排空 · \(b.workflowId) · \(b.total) 隻 · \(b.outcome)"
                + " · 跑了 \(b.runDuration.map(elapsed) ?? "?")"
                + " · \(b.audibility)"
        case .quotaTier(let q):
            return "T3 額度分級 \(q.from) → \(q.to)"
        }
    }

    /// 秒數畫成「12m 04s」。nil 由呼叫端處理成 "?" —— **不要在這裡把 nil 變成 0**，
    /// 「跑了 0m 00s」看起來像一個量到的數字。
    private static func elapsed(_ s: TimeInterval) -> String {
        let total = Int(s.rounded())
        return total < 60 ? "\(total)s"
                          : String(format: "%dm %02ds", total / 60, total % 60)
    }

    private static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }
}
