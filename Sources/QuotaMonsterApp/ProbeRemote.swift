import Foundation
import QuotaMonsterCore

/// `QuotaMonsterApp --probe-remote`：真的問一次 herdr，印出面板「遠端 REMOTE」那一區會說什麼。
///
/// ⚠️ **會真的執行 herdr**（它再經 SSH 去問遠端機器）—— 這是使用者主動下的指令，與偏好開關無關，
/// 與 `--probe-update` 會真的連網是同一個理由。跟 app 走同一條路：同一個 `RemoteMonitor.run`、
/// 同一個 `HerdrOutput`、同一個 `RemoteTracker`。
///
/// 結束碼：0 ＝ 每台都讀到了；1 ＝ 有機器讀不到（或整區只有一行說明）；2 ＝ 沒裝 herdr。
@MainActor
enum ProbeRemote {

    static func run() async -> Int32 {
        let home = FileManager.default.homeDirectoryForCurrentUser
        guard let exe = HerdrCommand.candidatePaths(home: home)
            .first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else {
            print("找不到 herdr（找過：\(HerdrCommand.candidatePaths(home: home).map(\.path).joined(separator: "、"))）")
            return 2
        }
        print("herdr：\(exe.path)")
        var t = RemoteTracker()
        let started = Date()
        let list = await RemoteMonitor.run(exe, HerdrCommand.machineList, home: home)
        print(String(format: "machine list：exit %@，%.2f 秒",
                     list.exitCode.map { "\($0)" } ?? "—", Date().timeIntervalSince(started)))
        t.machinesRead(HerdrOutput.machines(list), now: Date())
        for id in t.machineIds {
            guard let argv = HerdrCommand.agentList(machineId: id) else { continue }
            let s = Date()
            let run = await RemoteMonitor.run(exe, argv, home: home)
            print(String(format: "agent list（%@）：exit %@，%.2f 秒%@", String(id.prefix(8)),
                         run.exitCode.map { "\($0)" } ?? "—", Date().timeIntervalSince(s),
                         run.timedOut ? "，逾時" : ""))
            t.agentsRead(machineId: id, HerdrOutput.agents(run), now: Date())
        }
        print("")
        switch t.view(now: Date()) {
        case .hidden:
            print("整區不畫")
            return 2
        case .notice(let text):
            print("遠端 REMOTE：\(text)")
            return 1
        case .machines(let cards, let listNote):
            var ok = listNote == nil
            if let listNote { print("⚠ \(listNote)") }
            for c in cards {
                print("\(c.warning ? "⚠ " : "")\(c.label)　\(c.caption)")
                if let counts = c.counts {
                    print("  " + (c.note ?? counts.map(\.text).joined(separator: "　"))
                          + (c.countsDimmed ? "（調暗）" : ""))
                }
                for w in c.waiting {
                    let name = RemoteWords.waitingLabel(w)
                    print("  ▌\(name.main)\(name.sub.map { "  \($0)" } ?? "")　等你回覆")
                }
                if c.warning { ok = false }
            }
            return ok ? 0 : 1
        }
    }
}
