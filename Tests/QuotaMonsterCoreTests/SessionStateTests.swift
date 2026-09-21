import Testing
import Foundation
@testable import QuotaMonsterCore

/// 把註冊表記錄 + 存活判定衍生成 app 要顯示的東西。
///
/// 最重要的一條規則：**`.waiting` 就是「人類被擋住」。**
/// 這有二進位證據撐腰 —— 狀態機是 `{running:"busy", requires_action:"waiting", idle:"idle"}`，
/// 而被 subagent 卡住走的是 `delegatedActive` → busy 分支。
/// 所以 waiting 不會因為「在等子代理」而誤觸發。
@Suite("SessionState")
struct SessionStateTests {

    func session(_ status: SessionStatus, pid: Int32 = 100, id: String = "s1",
                 cwd: String = "/Users/me/Antigravity/F1") -> ClaudeSession {
        ClaudeSession(pid: pid, sessionId: id, cwd: cwd,
                      startedAt: Date(timeIntervalSince1970: 1_789_660_000),
                      status: status, name: "f1-e3")
    }

    /// 全部視為活著
    let allAlive = SessionStateResolver(isAlive: { _, _ in true })
    /// 全部視為死了
    let allDead = SessionStateResolver(isAlive: { _, _ in false })

    @Test("waiting 代表需要人類介入")
    func waitingMeansNeedsHuman() {
        let r = allAlive.resolve([session(.waiting(.inputNeeded))])
        #expect(r.first?.needsHuman == true)
        #expect(r.first?.waitingFor == .inputNeeded)
    }

    @Test("permission prompt 同樣需要人類介入")
    func permissionPromptAlsoNeedsHuman() {
        let r = allAlive.resolve([session(.waiting(.permissionPrompt))])
        #expect(r.first?.needsHuman == true)
    }

    @Test("busy 永遠不代表需要人類介入 —— 被 subagent 卡住走的就是 busy")
    func busyNeverMeansNeedsHuman() {
        let r = allAlive.resolve([session(.busy)])
        #expect(r.first?.needsHuman == false)
        #expect(r.first?.isWorking == true)
    }

    @Test("idle 既不忙也不需要人類介入")
    func idleIsNeitherWorkingNorBlocking() {
        let r = allAlive.resolve([session(.idle)])
        #expect(r.first?.needsHuman == false)
        #expect(r.first?.isWorking == false)
    }

    @Test("shell 算在工作中")
    func shellCountsAsWorking() {
        let r = allAlive.resolve([session(.shell)])
        #expect(r.first?.isWorking == true)
    }

    @Test("死掉的行程一律排除，無論檔案裡寫什麼狀態")
    func deadProcessIsExcludedRegardlessOfStatus() {
        #expect(allDead.resolve([session(.busy)]).isEmpty)
        #expect(allDead.resolve([session(.waiting(.inputNeeded))]).isEmpty)
    }

    @Test("專案名取自 cwd 的最後一段")
    func projectNameComesFromCwd() {
        let r = allAlive.resolve([session(.busy, cwd: "/Users/me/Antigravity/F1")])
        #expect(r.first?.project == "F1")
    }

    @Test("需要人類介入的排在最前面")
    func blockedSessionsSortFirst() {
        let r = allAlive.resolve([
            session(.busy, pid: 1, id: "a"),
            session(.idle, pid: 2, id: "b"),
            session(.waiting(.permissionPrompt), pid: 3, id: "c"),
        ])
        #expect(r.first?.session.sessionId == "c")
    }

    @Test("彙總數字：幾個在等你、幾個在工作")
    func summaryCounts() {
        let r = allAlive.resolve([
            session(.busy, pid: 1, id: "a"),
            session(.idle, pid: 2, id: "b"),
            session(.waiting(.inputNeeded), pid: 3, id: "c"),
            session(.shell, pid: 4, id: "d"),
        ])
        let s = SessionSummary(r)
        #expect(s.total == 4)
        #expect(s.blocked == 1)
        #expect(s.working == 2)   // busy + shell
        #expect(s.idle == 1)
    }
}
