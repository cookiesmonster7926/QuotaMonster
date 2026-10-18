import Foundation
import QuotaMonsterCore

/// `--measure-ranfor` —— 唯讀掃 `~/.claude/projects` 底下每一份**主** transcript，
/// 用 Core 的 `RanForCoverage` 算「會產生完成標記的回合裡，幾個算得出 ranFor」。
///
/// ⚠️ **只印計數與分位數，不印任何一行的內容、路徑或 session 名。**
/// 這支的輸出是要貼進 public repo 的文件的（第三節第 33 條）。
/// ⚠️ 它是〔代理量測〕：拿每一行的 timestamp 當 mtime 的代理，限制寫在 `RanForCoverage` 的檔頭。
enum MeasureRanFor {

    static func say(_ line: String) {
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }

    static func run() {
        let projects = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
        // 主 transcript ＝ `<slug>/<sessionId>.jsonl`。subagent 的在 `<slug>/<sessionId>/subagents/`，
        // 它們的完成不是 session 講完了，不算。
        let slugs = (try? FileManager.default.contentsOfDirectory(
            at: projects, includingPropertiesForKeys: nil)) ?? []
        var files: [URL] = []
        for slug in slugs {
            let items = (try? FileManager.default.contentsOfDirectory(
                at: slug, includingPropertiesForKeys: nil)) ?? []
            files += items.filter { $0.pathExtension == "jsonl" }
        }

        var unreadable = 0
        var merged: [RanForCoverage] = []
        for f in files {
            guard let data = try? Data(contentsOf: f) else { unreadable += 1; continue }
            var c = RanForCoverage()
            c.scan(data)
            merged.append(c)
        }

        let finishes = merged.reduce(0) { $0 + $1.finishes }
        let hits = merged.reduce(0) { $0 + $1.hits }
        let legacy = merged.reduce(0) { $0 + $1.legacyHits }
        let withTD = merged.reduce(0) { $0 + $1.withTurnDuration }
        let agree = merged.reduce(0) { $0 + $1.agreesWithTurnDuration }
        let ran = merged.flatMap(\.ranFor).sorted()

        func pct(_ a: Int, _ b: Int) -> String {
            b == 0 ? "—" : String(format: "%.1f%%", Double(a) * 100 / Double(b))
        }
        func q(_ p: Double) -> String {
            ran.isEmpty ? "—" : String(Int(ran[min(ran.count - 1, Int(Double(ran.count) * p))]))
        }

        say("主 transcript \(files.count) 份（讀不到 \(unreadable) 份）")
        say("完成（代理：end_turn 之後安靜 ≥ \(Int(CompletionTracker.settleWindow)) 秒或到檔尾）：\(finishes)")
        say("新作法算得出 ranFor：\(hits)/\(finishes) = \(pct(hits, finishes))")
        for m in RanForCoverage.Miss.allCases {
            let n = merged.reduce(0) { $0 + ($1.misses[m] ?? 0) }
            say("  算不出來 · \(m.rawValue)：\(n)（\(pct(n, finishes))）")
        }
        say("舊作法（模擬，只算「有值」）：\(legacy)/\(finishes) = \(pct(legacy, finishes))")
        say("ranFor 秒數 p50 \(q(0.5)) · p90 \(q(0.9)) · max \(ran.last.map { String(Int($0)) } ?? "—")"
              + " · ≥ \(Int(FinishGlow.minimumInterestingRun)) 秒：\(ran.filter { $0 >= FinishGlow.minimumInterestingRun }.count)")
        say("與 system/turn_duration 對照（|差| ≤ \(Int(RanForCoverage.agreementSeconds)) 秒）："
              + "\(agree)/\(withTD) = \(pct(agree, withTD))"
              + " · ranFor 較長 \(merged.reduce(0) { $0 + $1.longerThanTurnDuration })"
              + " · 較短 \(merged.reduce(0) { $0 + $1.shorterThanTurnDuration })")
    }
}
