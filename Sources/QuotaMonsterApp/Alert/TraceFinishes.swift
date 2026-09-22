import AppKit
import QuotaMonsterCore

/// `--trace-finishes [秒數]` —— 用 Core 的同一套偵測器對著實時資料跑，
/// 把每一拍看到什麼、決定了什麼印出來。
///
/// **為什麼需要它：** 完成訊號一天只出現幾次，而它沒出現的時候畫面上什麼線索
/// 都沒有 ——「還沒安靜滿 90 秒」「尾端是 tool_use」「讀不到尾端」「看到了但
/// 不是我們見證的」「跑不夠久所以選單列不亮」，五種原因長得一模一樣。
/// 這支把中間那一段攤開。
///
/// ⚠️ **這是一個影子引擎。** 它是獨立行程、自己剛開機的 `CompletionTracker`，
/// 所以它的「第一次看到」是**現在**，不是選單列上那個 app 的。
/// 因此它一定會把此刻已經完成的那些判成「不是我們見證的」而丟掉 ——
/// 那是對的行為，不是 bug。要看它真的亮，得在追蹤期間讓某個 session 跑完一輪。
@MainActor
enum TraceFinishes {

    /// ⚠️ 直接寫 fd 1，不用 `print` —— 理由見 `TraceAlerts.say`。
    static func say(_ line: String) {
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }

    static func run(seconds: Int) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let registry = SessionRegistryReader()
        let resolver = SessionDirectoryResolver()
        let reader = TurnCompletionReader()
        let projects = home.appendingPathComponent(".claude/projects")

        var tracker = CompletionTracker(
            readTail: { reader.read($0) },
            readTurnStart: { reader.readTurnStart($0) },
            modifiedAt: { reader.modifiedAt($0) })
        var finishes: [String: SessionFinish] = [:]
        var lastLine: [String: String] = [:]
        var paths: [String: URL] = [:]
        var tick = 0

        say("追蹤 \(seconds) 秒 —— 每 3 秒一拍，只在有變化時印。")
        say("沉澱窗 \(Int(CompletionTracker.settleWindow)) 秒，"
              + "選單列門檻 \(Int(FinishGlow.minimumInterestingRun)) 秒。")
        say("⚠️ 這是影子引擎：它「第一次看到」是現在，所以此刻已經完成的都會被"
              + "當成「不是我們見證的」而丟掉 —— 那是對的。")
        say(String(repeating: "─", count: 72))

        let deadline = Date().addingTimeInterval(TimeInterval(seconds))
        while Date() < deadline {
            let now = Date()
            tick += 1

            let raw = registry.read(directory: home.appendingPathComponent(".claude/sessions"))
            let sessions = SessionStateResolver().resolve(raw)

            var transcripts: [String: URL] = [:]
            for s in sessions {
                let id = s.session.sessionId
                if let cached = paths[id] { transcripts[id] = cached; continue }
                guard let u = resolver.transcript(sessionId: id, projectsRoot: projects)
                else { continue }
                paths[id] = u
                transcripts[id] = u
            }

            // 每個 session 現在是什麼樣子 —— 有變化才印。
            for s in sessions {
                let id = s.session.sessionId
                let name = s.session.name ?? String(id.prefix(8))
                guard let url = transcripts[id] else {
                    if lastLine[name] != "沒有 transcript" {
                        say("[\(stamp())] \(pad(name))找不到 transcript"
                              + "（沒有 <slug>/<sessionId>.jsonl）")
                        lastLine[name] = "沒有 transcript"
                    }
                    continue
                }
                let mtime = reader.modifiedAt(url)
                let quiet = mtime.map { now.timeIntervalSince($0) } ?? -1
                let settled = quiet >= CompletionTracker.settleWindow
                // 只在沉澱之後才讀尾端 —— 與正式路徑同一條規矩。
                let readout = settled ? reader.read(url) : nil
                // ⚠️ 判斷「有沒有變」的鍵**不含任何秒數** —— 秒數每一拍都在變，
                // 拿它當鍵就等於每拍都印，而「只在有變化時印」那句承諾就沒了。
                // 這與 `--trace-alerts` 那一行犯過的是同一個錯。
                let key = settled ? "已沉澱|\(readout.map(kind) ?? "")" : "安靜"
                if lastLine[name] != key {
                    let detail = readout.map(describe) ?? "（還沒安靜滿窗，不讀）"
                    say("[\(stamp())] \(pad(name))"
                          + "\(settled ? "已沉澱" : "安靜 \(Int(quiet))s") · \(detail)")
                    lastLine[name] = key
                }
            }

            let out = tracker.update(CompletionInput(transcripts: transcripts), now: now)
            for f in out.finishes {
                finishes[f.sessionId] = f
                let name = sessions.first { $0.session.sessionId == f.sessionId }?
                    .session.name ?? String(f.sessionId.prefix(8))
                say("[\(stamp())] ✓ 完成  \(pad(name))"
                      + "\(FinishCaption.ranFor(f.ranFor) ?? "跑了多久算不出來")")
            }
            if !out.wrote.isEmpty {
                let names = out.wrote.map { id in
                    sessions.first { $0.session.sessionId == id }?.session.name
                        ?? String(id.prefix(8))
                }
                say("[\(stamp())] ✎ 又動了  \(names.sorted().joined(separator: ", "))")
            }
            finishes = FinishCaption.prune(finishes, wrote: out.wrote, now: now)

            let glow = FinishGlow.menuBar(Array(finishes.values), now: now)
            // ⚠️ **不亮有三個不同的原因，而它們長得一模一樣。**
            // 〔實測 2026-09-22，53 分鐘 / 957 拍 / 4–5 個 session〕產生了 8 個標記，
            // 選單列**一次都沒亮**。光看「選單列 none」分不出是哪一種：
            //   (a) 沒有標記   (b) 最新那個 `ranFor == nil`（算不出跑多久）
            //   (c) 最新那個跑得不夠久（< minimumInterestingRun 600 秒）
            // 「訊號該不該出聲」這個問題**必須先分得出 (b) 與 (c)** ——
            // (b) 是量測缺口，(c) 是門檻訂得對不對。所以這裡把最新那個的
            // `ranFor` 一起印出來，不要讓下一個人再猜一次。
            let newest = finishes.values.max(by: { $0.finishedAt < $1.finishedAt })
            let why: String
            if finishes.isEmpty {
                why = "沒有標記"
            } else if let r = newest?.ranFor {
                why = Int(r) >= Int(FinishGlow.minimumInterestingRun)
                    ? "最新的跑了 \(Int(r))s（夠久）"
                    : "最新的只跑了 \(Int(r))s < \(Int(FinishGlow.minimumInterestingRun))s"
            } else {
                why = "最新的算不出跑多久（ranFor = nil）"
            }
            let glowLine = "選單列 \(glow) · 手上有 \(finishes.count) 個標記 · \(why)"
            if lastLine["__glow"] != glowLine {
                say("[\(stamp())] ◆ \(glowLine)")
                lastLine["__glow"] = glowLine
            }

            Thread.sleep(forTimeInterval: DataStore.refreshInterval)
        }
        say(String(repeating: "─", count: 72))
        say("追蹤結束，共 \(tick) 拍。手上有 \(finishes.count) 個完成標記。")
    }

    private static func pad(_ s: String) -> String {
        s.padding(toLength: 14, withPad: " ", startingAt: 0)
    }

    /// 只取「哪一類」，不含秒數 —— 給變化偵測用。
    private static func kind(_ r: TurnReadout) -> String {
        switch r {
        case .finished:     return "finished"
        case .unfinished:   return "unfinished"
        case .inconclusive: return "inconclusive"
        }
    }

    private static func describe(_ r: TurnReadout) -> String {
        switch r {
        case .finished(let e):
            return "尾端 end_turn（\(Int(Date().timeIntervalSince(e.finishedAt)))s 前）"
        case .unfinished:   return "尾端還在跑（tool_use，或後面有真人訊息）"
        case .inconclusive: return "⚠️ 讀不到尾端 —— 不是證據，不發也不熄"
        }
    }

    private static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }
}
