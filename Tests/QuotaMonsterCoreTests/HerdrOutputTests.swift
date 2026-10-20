import Testing
import Foundation
@testable import QuotaMonsterCore

/// herdr 的指令與輸出 —— 遠端機器的 session 唯一的來源。
///
/// 測試資料是**合成**的：形狀照 herdr 0.9.3 的 `machine list --json` 與 `agent list`
/// 〔實測 2026-10-20，只看 key 與型別〕，值全部是編的（機器名、路徑、標題）。
@Suite("herdr 的指令與輸出")
struct HerdrOutputTests {

    func run(_ json: String, exit: Int32? = 0, stderr: String = "",
             timedOut: Bool = false, launchFailed: Bool = false) -> HerdrRun {
        HerdrRun(exitCode: exit, stdout: Data(json.utf8), stderr: Data(stderr.utf8),
                 timedOut: timedOut, launchFailed: launchFailed)
    }

    func agents(_ rows: String) -> String {
        #"{"id":"cli:agent:list","result":{"type":"agent_list","agents":["# + rows + "]}}"
    }

    // MARK: - 指令

    @Test("--machine 吃 machine list 的 id；argv 不經 shell")
    func agentListArgv() {
        #expect(HerdrCommand.agentList(machineId: "f00dbabe42")
                == ["--machine", "f00dbabe42", "agent", "list"])
        // agent list 本來就輸出 JSON，加 --json 反而 exit 2〔實測〕
        #expect(!(HerdrCommand.agentList(machineId: "abc") ?? []).contains("--json"))
        #expect(HerdrCommand.machineList == ["machine", "list", "--json"])
    }

    @Test("machine id 走白名單：- 開頭（會被當成旗標）、空白、斜線、太長、空字串都拒絕")
    func machineIdWhitelist() {
        for bad in ["-x", "--help", "a b", "a/b", "", String(repeating: "a", count: 65),
                    "a\u{0}b", "a\nb", "ä"] {
            #expect(HerdrCommand.agentList(machineId: bad) == nil, "\(bad.debugDescription)")
        }
        #expect(HerdrCommand.agentList(machineId: String(repeating: "a", count: 64)) != nil)
        #expect(HerdrCommand.agentList(machineId: "a_b.c-d") != nil)
    }

    @Test("GUI app 的 PATH 找不到 ~/.local/bin —— 候選路徑自己列，家目錄那個排第一")
    func candidatePaths() {
        let home = URL(fileURLWithPath: "/Users/someone")
        let paths = HerdrCommand.candidatePaths(home: home).map(\.path)
        #expect(paths.first == "/Users/someone/.local/bin/herdr")
        #expect(paths.contains("/opt/homebrew/bin/herdr"))
    }

    // MARK: - 機器清單

    @Test("機器清單：只留 enabled 的；label 剝控制字元")
    func machines() {
        let out = run(#"""
        [{"id":"aaa111","label":"WIN-DESKTOP","target":"win","session":"default","enabled":true,"selected":false},
         {"id":"bbb222","label":"OFF\u0007BOX","target":"off","session":"default","enabled":false,"selected":false},
         {"id":"ccc333","label":"LAB\u001b[31m","target":"lab","session":"default","enabled":true,"selected":false}]
        """#)
        guard case .success(let ms) = HerdrOutput.machines(out) else { Issue.record("應該讀得到"); return }
        #expect(ms.map(\.id) == ["aaa111", "ccc333"])
        #expect(ms[1].label == "LAB[31m")
    }

    @Test("機器清單：id 過不了白名單的那台整台跳過（不讓它變成 argv）")
    func machineWithBadIdSkipped() {
        let out = run(#"[{"id":"-oProxyCommand=x","label":"EVIL","enabled":true}]"#)
        guard case .success(let ms) = HerdrOutput.machines(out) else { Issue.record("應該讀得到"); return }
        #expect(ms.isEmpty)
    }

    @Test("機器清單：沒有 label 用 id 前 8 碼")
    func machineWithoutLabel() {
        let out = run(#"[{"id":"0123456789abcdef","enabled":true}]"#)
        guard case .success(let ms) = HerdrOutput.machines(out) else { Issue.record("應該讀得到"); return }
        #expect(ms.first?.label == "01234567")
    }

    // MARK: - agent 清單

    @Test("agent 清單：只留 claude；四種狀態照認，不認得的是 unknown")
    func agentStatuses() {
        let out = run(agents(#"""
        {"agent":"claude","agent_status":"working","cwd":"/home/u/train-rl","terminal_title_stripped":"訓練"},
        {"agent":"claude","agent_status":"blocked","cwd":"C:\\Users\\u\\paper","terminal_title_stripped":"校稿"},
        {"agent":"claude","agent_status":"done","cwd":"/x/dataset"},
        {"agent":"claude","agent_status":"idle","cwd":"/x/env"},
        {"agent":"claude","agent_status":"pondering","cwd":"/x/new"},
        {"agent":"codex","agent_status":"working","cwd":"/x/other"}
        """#))
        guard case .success(let rows) = HerdrOutput.agents(out) else { Issue.record("應該讀得到"); return }
        #expect(rows.map(\.status) == [.working, .blocked, .done, .idle, .unknown])
        #expect(rows.map(\.project) == ["train-rl", "paper", "dataset", "env", "new"])
        #expect(rows[1].title == "校稿")
        #expect(rows[2].title == nil)
    }

    @Test("agent 清單：沒有 agent_status 的列是 unknown，不是 idle（沒看到 ≠ 閒著）")
    func missingStatusIsUnknown() {
        let out = run(agents(#"{"agent":"claude","cwd":"/x/a"}"#))
        guard case .success(let rows) = HerdrOutput.agents(out) else { Issue.record("應該讀得到"); return }
        #expect(rows.first?.status == .unknown)
    }

    @Test("agent 清單：一台機器上沒有任何 claude → 空的，是讀成功（正面證據），不是失敗")
    func emptyAgentListIsSuccess() {
        #expect(HerdrOutput.agents(run(agents(""))) == .success([]))
    }

    @Test("字串：剝 C0／DEL／C1 控制字元、頭尾空白；截到上限；剝完是空的回 nil")
    func clean() {
        #expect(HerdrOutput.clean("  a\u{0}b\u{7}c\u{7f}d\u{85}e\n ", max: 200) == "abcde")
        #expect(HerdrOutput.clean(String(repeating: "字", count: 300), max: 200)?.count == 200)
        #expect(HerdrOutput.clean(" \u{1b}\t ", max: 200) == nil)
    }

    @Test("專案名：cwd 的最後一段，/ 與 \\ 都認；結尾的分隔符不算；根目錄回 nil")
    func project() {
        #expect(HerdrOutput.project(cwd: "/home/u/proj/") == "proj")
        #expect(HerdrOutput.project(cwd: #"C:\Users\u\proj"#) == "proj")
        #expect(HerdrOutput.project(cwd: "/") == nil)
        #expect(HerdrOutput.project(cwd: nil) == nil)
    }

    // MARK: - 失敗分類（「讀不到」有好幾種，畫面要說得出是哪一種）

    @Test("server 沒在跑：exit 1、stderr 是 JSON 的 server_not_running〔實測〕")
    func serverNotRunning() {
        let out = run("", exit: 1, stderr: #"{"id":"cli:agent:list","error":{"code":"server_not_running","message":"no herdr server is running at /x/herdr.sock; run `herdr` to start or attach it"}}"#)
        #expect(HerdrOutput.agents(out) == .failure(.serverNotRunning))
        #expect(HerdrOutput.machines(out) == .failure(.serverNotRunning))
    }

    @Test("unknown machine：exit 2、純文字〔實測：用 target 而不是 id 時〕")
    func unknownMachine() {
        let out = run("", exit: 2, stderr: "unknown machine 'win'")
        #expect(HerdrOutput.agents(out) == .failure(.unknownMachine))
    }

    @Test("其他 herdr 錯誤：帶著它的 code（連不上遠端多半是這種）")
    func otherHerdrError() {
        let out = run("", exit: 1, stderr: #"{"id":"cli:agent:list","error":{"code":"endpoint_unavailable","message":"x"}}"#)
        #expect(HerdrOutput.agents(out) == .failure(.herdrError(code: "endpoint_unavailable")))
        #expect(HerdrOutput.agents(run("", exit: 1, stderr: "boom")) == .failure(.herdrError(code: nil)))
    }

    @Test("逾時與啟動不了，優先於 exit code")
    func timeoutAndLaunch() {
        #expect(HerdrOutput.agents(run("", exit: 15, timedOut: true)) == .failure(.timedOut))
        // ⚠️ 啟動不了（暫存目錄建不起來、檔案在但不可執行）**不是**「沒裝 herdr」——
        // 沒裝的話整區不畫；這裡要畫出原因（code review：曾經對映成 notInstalled，整區靜默消失）。
        #expect(HerdrOutput.agents(run("", exit: nil, launchFailed: true)) == .failure(.couldNotRun))
    }

    @Test("unknown machine 只認 exit 2 —— 其他錯誤的訊息裡剛好有那幾個字不算")
    func unknownMachineNeedsExit2() {
        let out = run("", exit: 1, stderr: #"{"error":{"code":"remote_failed","message":"unknown machine state"}}"#)
        #expect(HerdrOutput.agents(out) == .failure(.herdrError(code: "remote_failed")))
    }

    @Test("exit 0 但讀不懂：incompatible，不是「沒有 session」")
    func garbageIsNotEmpty() {
        #expect(HerdrOutput.agents(run("not json")) == .failure(.incompatible))
        #expect(HerdrOutput.agents(run(#"{"id":"x","result":{"type":"other"}}"#)) == .failure(.incompatible))
        #expect(HerdrOutput.machines(run(#"{"not":"a list"}"#)) == .failure(.incompatible))
    }

    @Test("protocol 不合：incompatible")
    func protocolMismatch() {
        let out = run("", exit: 1, stderr: #"{"error":{"code":"protocol_mismatch","message":"x"}}"#)
        #expect(HerdrOutput.agents(out) == .failure(.incompatible))
    }
}
