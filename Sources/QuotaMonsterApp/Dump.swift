import Foundation
import QuotaMonsterCore

/// `QuotaMonsterApp --dump`：把 Core 從真實資料讀到的東西印出來。
///
/// 這裡**沒有任何新邏輯** —— 只是把已經測過的函式接到 stdout，
/// 用來確認資料層在真實機器上的行為與 fixture 一致。
enum Dump {
    static func run() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let now = Date()

        print("QuotaMonster — 資料層真實資料驗證")
        print(String(repeating: "─", count: 58))

        // ── 額度來源一：~/.claude.json ──────────────────────────
        let claudeJSON = home.appendingPathComponent(".claude.json")
        var fromClaudeJSON: UsageSnapshot?
        do {
            fromClaudeJSON = try ClaudeJSONUsageReader().read(claudeJSON, now: now,
                                                              expectedAccount: nil)
            if let snap = fromClaudeJSON {
                let age = Int(now.timeIntervalSince(snap.fetchedAt))
                print("來源 A  ~/.claude.json · cachedUsageUtilization")
                print("        抓取於 \(age) 秒前（\(age / 60) 分鐘）  →  \(describe(snap.freshness))")
                print("        5 小時  \(describe(snap.fiveHour, now: now))")
                print("        7 天    \(describe(snap.sevenDay, now: now))")
                for (k, w) in snap.perModel.sorted(by: { $0.key < $1.key }) {
                    print("        \(k)  \(describe(w, now: now))")
                }
            } else {
                print("來源 A  ~/.claude.json 沒有快取，或帳號不符")
            }
        } catch {
            print("來源 A  讀取失敗：\(error)")
        }

        // ── 額度來源二：statusline tee ──────────────────────────
        print(String(repeating: "·", count: 58))
        let cacheDir = StatusLineCacheReader.defaultDirectory(home: home)
        let payloads = StatusLineCacheReader().read(directory: cacheDir, now: now)
        if payloads.isEmpty {
            print("來源 B  statusline tee 快取是空的")
            print("        \(cacheDir.path)")
            print("        沒裝 tee，或狀態列還沒重新渲染過。"
                  + "安裝：bash scripts/install_statusline_tee.sh --apply")
        } else {
            print("來源 B  statusline tee · \(payloads.count) 個 session 的 payload")
            print("        \(cacheDir.path)")
            for p in payloads.sorted(by: { $0.capturedAt > $1.capturedAt }) {
                let age = Int(now.timeIntervalSince(p.capturedAt))
                let id = p.sessionId.map { String($0.prefix(8)) } ?? "(無 session_id)"
                print("        \(id)  \(age) 秒前  \(describeContext(p))")
                print("                  5 小時 \(describe(p.fiveHour, now: now))")
                print("                  7 天   \(describe(p.sevenDay, now: now))")
                if let s = p.spendLimit {
                    print("                  spend  \(describe(s, now: now))")
                }
            }
        }

        // ── 最後採用哪一個 ──────────────────────────────────────
        print(String(repeating: "·", count: 58))
        let pickedUsage = UsageSourceSelector.pick(claudeJSON: fromClaudeJSON,
                                                  statusLine: payloads, now: now)
        if let picked = pickedUsage ?? UsageSourceSelector.pick(claudeJSON: fromClaudeJSON,
                                                 statusLine: payloads, now: now) {
            let label = picked.source == .statusLine ? "statusline tee（來源 B）"
                                                     : "~/.claude.json（來源 A）"
            let age = Int(now.timeIntervalSince(picked.snapshot.fetchedAt))
            // 不可以無條件寫「因為它比較新」。statusline 的 payload 存在但都沒帶
            // 額度窗口時，選中的是 16 小時前的 ~/.claude.json —— 那句話會變成
            // 在一份「1 秒前」的 payload 底下宣稱 57600 秒前的東西比較新。
            let usable = payloads.filter(\.hasAnyWindow).count
            let reason: String
            if picked.source == .statusLine {
                reason = "它比較新（\(age) 秒前）"
            } else if payloads.isEmpty {
                reason = "沒有 statusline 快取可用"
            } else if usable == 0 {
                reason = "\(payloads.count) 份 statusline payload 都沒有帶額度窗口"
            } else {
                reason = "它比較新（\(age) 秒前）"
            }
            print("採用    \(label)，因為\(reason)")
            print("        5 小時  \(describe(picked.snapshot.fiveHour, now: now))")
            print("        7 天    \(describe(picked.snapshot.sevenDay, now: now))")
            print("        新鮮度  \(describe(picked.snapshot.freshness))")
            print()
            print("        ↑ 這兩個數字必須與你狀態列上的 5h/7d 相同。不同就是有 bug。")
        } else {
            print("採用    兩個來源都沒有可用讀數 —— 面板會顯示「—」而不是 0%")
        }

        // ── 分模型（只有 ~/.claude.json 有）──────────────────────
        print(String(repeating: "·", count: 58))
        if let b = try? ClaudeJSONUsageReader().readScoped(claudeJSON, now: now), !b.scoped.isEmpty {
            let age = Int(b.age(now: now))
            print("分模型  來自 ~/.claude.json 的 limits 陣列（\(age / 60) 分鐘前）")
            for e in b.scoped.sorted(by: { $0.percent > $1.percent }) {
                print("        \(e.modelName.padded(12)) \(describe(UsageWindow(percent: e.percent, resetsAt: e.resetsAt), now: now))")
            }
            print("        ↑ 這一欄與上面那兩個數字**不是同一個來源**，面板上會標出年齡。")
        } else {
            print("分模型  ~/.claude.json 沒有 limits 項目")
        }

        // ── 時間序列 ────────────────────────────────────────────
        print(String(repeating: "·", count: 58))
        let historyFile = UsageHistory.defaultURL(home: home)
        let samples = UsageHistory().read(historyFile, now: now)
        if samples.isEmpty {
            print("歷史    還沒有取樣點：\(historyFile.path)")
        } else {
            let span = now.timeIntervalSince(samples[0].at)
            print("歷史    \(samples.count) 個取樣點，最早的在 \(Int(span / 3600)) 小時前")
            print("        \(historyFile.path)")
            for s in samples.suffix(3) {
                let ago = Int(now.timeIntervalSince(s.at))
                print("        \(ago) 秒前  5h=\(s.fiveHour.map(String.init) ?? "—")  "
                      + "7d=\(s.sevenDay.map(String.init) ?? "—")")
            }
            if span < 2 * 86400 {
                print("        （每日長條圖要約兩天的資料才有意義）")
            }
        }

        // ── 展望 ───────────────────────────────────────────────
        //
        // 這一段存在的理由跟拒絕要具名是同一個：面板上「沒有箭頭」
        // 與「沒有投射」看起來都是一片安靜，只有這裡說得出為什麼。
        print(String(repeating: "·", count: 58))
        if let u = UsageSourceSelector.pick(claudeJSON: fromClaudeJSON,
                                            statusLine: payloads, now: now)?.snapshot {
            let five = UsageOutlook.fiveHour(u.fiveHour, freshness: u.freshness,
                                             measuredAt: u.fetchedAt, samples: samples)
            let seven = UsageOutlook.sevenDay(u.sevenDay, freshness: u.freshness,
                                              measuredAt: u.fetchedAt)
            print("展望    5 小時  \(outlookLine(five))")
            print("        7 天    \(outlookLine(seven))")
            if let five {
                print("        ↑ 面板第一欄的註腳就是這一句的短版。")
                print("        \(OutlookCaption.evidence(five))")
            }
        } else {
            print("展望    沒有可信讀數，什麼都不投射")
        }

        // ── session ────────────────────────────────────────────
        print(String(repeating: "─", count: 58))
        let dir = home.appendingPathComponent(".claude/sessions")
        let raw = SessionRegistryReader().read(directory: dir)
        let live = SessionStateResolver().resolve(raw)
        let summary = SessionSummary(live)
        print("Session  註冊表 \(raw.count) 筆 → 存活 \(summary.total) 筆"
              + "（\(raw.count - summary.total) 筆是殭屍，已被 pid+啟動時間比對濾掉）")
        let projectsForTitles = home.appendingPathComponent(".claude/projects")
        let resolverForTitles = SessionDirectoryResolver()
        print("         \(summary.blocked) 個在等你 · \(summary.working) 個工作中 · \(summary.idle) 個閒置")
        // ⚠️ 與面板同一套判準（`SessionTitle`）。診斷若顯示 `rl-1b` 而面板顯示
        // `0922作業`，使用者會以為兩邊看的不是同一個 session —— 規矩 28。
        func shownName(_ session: ClaudeSession) -> String {
            let fallback = session.name ?? String(session.sessionId.prefix(8))
            guard SessionTitle.isPlaceholder(session.nameSource) else { return fallback }
            let title = resolverForTitles.transcript(sessionId: session.sessionId,
                                                     projectsRoot: projectsForTitles)
                .flatMap { SessionTitle.aiTitle(inTranscript: $0) }
            return title ?? fallback
        }

        for s in live {
            let mark = s.needsHuman ? "⏸" : (s.isWorking ? "▶" : "·")
            let reason = s.waitingFor.map { "  ← \($0.rawValue)" } ?? ""
            let name = shownName(s.session)
            print("  \(mark) \(name.padded(14)) \(s.project.padded(22)) "
                  + "pid \(s.session.pid)\(reason)")
        }
        // ── 每日長條圖 ──────────────────────────────────────────
        // ⚠️ 面板上那七根看起來一樣的「很矮」與「不知道」差很多，
        // 而圖上分不出一根 3% 與一根 0%。這裡印出數字。
        print(String(repeating: "─", count: 58))
        let barsOrNil = pickedUsage?.snapshot.sevenDay?.resetsAt.map {
            DailyUsage.bars(samples: UsageHistory().read(UsageHistory.defaultURL(home: home), now: now),
                            marks: WatchLog().read(WatchLog.defaultURL(home: home)),
                            resetsAt: $0, now: now)
        }
        if let bars = barsOrNil {
            let f = DateFormatter(); f.dateFormat = "M/d HH:mm"
            print("每日     7 天視窗切成七天（邊界＝resetsAt−7天，不是午夜）")
            var sum = 0
            for b in bars {
                let what: String
                switch b.state {
                case .notYet:              what = "還沒到"
                case .unknown:             what = "不知道（那時沒在看）"
                case .measured(let p):     what = "\(p)%"; sum += p
                case .unverified(let p):   what = "\(p)%  ⚠️ 日界附近沒紀錄，歸屬可能落在隔壁"; sum += p
                }
                print("  \(f.string(from: b.start)) → \(f.string(from: b.end))   \(what)")
            }
            // ⚠️ 「相加＝7 天已用」只在**七根都說得出數字**時才成立。
            // 有 unknown 的時候它本來就對不上 —— 把那句話無條件印出來，
            // 使用者會去追一個不存在的 bug（規矩 28）。
            let gaps = bars.filter { $0.state == .unknown }.count
            let pending = bars.filter { $0.state == .notYet }.count
            if gaps == 0 && pending == 0 {
                print("  七根相加 = \(sum)%   ← 必須等於上面 7 天那一欄，不等就是有 bug")
            } else {
                print("  已知的相加 = \(sum)%"
                      + "（\(gaps) 天不知道、\(pending) 天還沒到，所以**不會**等於 7 天那一欄）")
            }
        } else {
            print("每日     畫不出來：沒有 7 天窗口的重置時間")
        }

        // ── agent 樹 ────────────────────────────────────────────
        print(String(repeating: "─", count: 58))
        let projects = home.appendingPathComponent(".claude/projects")
        let resolver = SessionDirectoryResolver()
        let builder = AgentTreeBuilder()
        for s in live {
            guard let paths = resolver.locate(sessionId: s.session.sessionId,
                                              projectsRoot: projects) else {
                print("Agent  \(shownName(s.session))：找不到 session 目錄")
                continue
            }
            let tree = builder.build(paths: paths,
                                     sessionId: s.session.sessionId,
                                     sessionStartedAt: s.session.startedAt, now: now)
            let name = shownName(s.session)
            // ⚠️ 這一行原本寫「N 隻確定在跑」。一般 Agent subagent 改用代理量測之後
            // 那個「確定」就是謊 —— 說得出幾隻是推的，才有資格說總數。
            let likely = tree.likelyRunningAgentCount
            let suffix = likely > 0 ? "（其中 \(likely) 隻是由 transcript 活動推定的）" : ""
            print("Agent  \(name) · \(s.project)  →  \(tree.runningAgentCount) 隻在跑\(suffix)")
            for a in tree.agents {
                print("         ├ \(a.meta.agentType)  \(a.meta.description.prefix(40))"
                      + "  [\(describe(a.runState))]"
                      + (a.isLinkedToTranscript ? "" : "  ⚠ transcript 內找不到對應的 tool_use"))
                for c in a.children {
                    print("         │  └ \(c.meta.agentType)  \(c.meta.description.prefix(36))")
                }
            }
            for wf in tree.workflows {
                print("         ├ workflow \(wf.workflowId)"
                      + (wf.latestPhase.map { " · \($0)" } ?? "")
                      + "  \(wf.finishedCount)/\(wf.total) 完成，\(wf.runningCount) 執行中")
                for a in wf.agents where a.runState == .running {
                    print("         │  ▶ \(a.meta.description.prefix(44))")
                }
            }
        }
        print(String(repeating: "─", count: 58))
    }

    static func describe(_ r: AgentRunState) -> String {
        switch r {
        case .running: return "執行中"
        // ⚠️ 括號是刻意的：它是推定的，不是讀到的（見 `AgentActivity`）。
        case .likelyRunning: return "（推定在跑）"
        case .finished: return "已收尾"
        case .unknown: return "未知"
        }
    }

    static func describe(_ f: Freshness) -> String {
        switch f {
        case .live: return "live（5 分鐘內）"
        case .aging(let m): return "aging（\(m) 分鐘前）"
        case .expired: return "expired（超過 60 分鐘，Claude Code 自己也會丟棄）"
        }
    }

    static func describeContext(_ p: StatusLinePayload) -> String {
        guard let used = p.contextUsedPercent else { return "context —（尚無讀數）" }
        let size = p.contextWindowSize.map { $0 >= 1_000_000 ? "1M" : "\($0 / 1000)k" } ?? "?"
        let tokens = p.totalInputTokens.map { " · \($0 / 1000)k tokens" } ?? ""
        return "context \(used)% of \(size)\(tokens)"
    }

    static func describe(_ w: UsageWindow?, now: Date) -> String {
        // ⚠️ nil 有**兩個**來源，而這一行看不出是哪一個：(a) 這個方案沒有這個窗口；
        // (b) `WindowExpiry` 因為 resets_at 已過而把它丟掉。以前只有 (a) 會發生，
        // 所以斷言 (a) 是對的；2026-09-21 讓 ~/.claude.json 也擋過期之後 (b) 就變成
        // 常態了（那個檔案從 09-17 凍住），再寫死 (a) 就是規矩 28 說的「診斷說謊」。
        // 要分辨得回去讀原始 JSON —— 在這裡不值得，所以誠實地寫出兩種可能。
        guard let w else { return "—（沒有讀數：這個方案沒有這個窗口，或它已經重置；都與 0% 不同）" }
        var s = "已用 \(w.percent)%"
        if let r = w.resetsAt {
            if let left = ResetTimestamp.remaining(until: r, now: now) {
                s += "，\(Int(left / 60)) 分鐘後重置"
            } else {
                s += "，重置時間已過"
            }
        }
        return s
    }

    static func outlookLine(_ outlook: UsageOutlook?) -> String {
        guard let o = outlook else { return "—（投射說不出話：窗口才剛重置，或讀數過期）" }
        let p = o.projection
        var out = String(format: "已過 %.0f%%，均速 %.2f %%/小時 → ",
                         p.elapsedFraction * 100, p.burnPerHour)
        switch p.outcome {
        case .resetsFirst(let n): out += "重置時約 \(n)%"
        case .exceedsWindow: out += o.exceedsConfirmed ? "會觸頂（兩個都同意）"
                                                       : "均速說 >100%，最近速率未證實"
        case .exhausted: out += "已觸頂"
        }
        switch o.burn {
        case .estimate(let e):
            out += String(format: "；最近 %.2f（%.2f–%.2f）", e.percentPerHour,
                          e.lowerPercentPerHour, e.upperPercentPerHour)
            out += o.trend == .faster ? " ↑" : o.trend == .slower ? " ↓" : " ＝"
        case .refused(let why):
            out += "；最近速率：\(OutlookCaption.refusalText(why))"
        }
        return out
    }
}

private extension String {
    func padded(_ n: Int) -> String {
        count >= n ? self : self + String(repeating: " ", count: n - count)
    }
}
