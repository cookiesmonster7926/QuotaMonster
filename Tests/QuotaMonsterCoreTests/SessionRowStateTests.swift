import Testing
import Foundation
@testable import QuotaMonsterCore

/// 面板一列 session 的判斷。原本寫在 `SessionRow`（App 層）裡，碰不到測試 ——
/// 規矩 4。這些測試**先鎖住搬移前的行為**：每一則的期望值都是照搬移前的
/// `SessionRow.swift` 逐行抄下來的，不是重新設計的答案。
@Suite("SessionRowStatus —— header 右側畫哪一種狀態")
struct SessionRowStatusTests {

    func live(_ status: SessionStatus) -> LiveSession {
        LiveSession(session: ClaudeSession(
            pid: 100, sessionId: "s1", cwd: "/tmp/synthetic/proj",
            startedAt: Date(timeIntervalSince1970: 1_000_000), status: status))
    }

    let finish = SessionFinish(sessionId: "s1",
                               finishedAt: Date(timeIntervalSince1970: 1_000_500),
                               ranFor: 60)

    @Test("busy 與 shell 都是 BUSY —— 與 LiveSession.isWorking 同一個判準")
    func busyAndShellAreBusy() {
        #expect(SessionRowStatus(session: live(.busy), finish: nil) == .busy)
        #expect(SessionRowStatus(session: live(.shell), finish: nil) == .busy)
        #expect(SessionRowStatus.busy.badge == "BUSY")
    }

    @Test("idle 是 IDLE")
    func idleIsIdle() {
        #expect(SessionRowStatus(session: live(.idle), finish: nil) == .idle)
        #expect(SessionRowStatus.idle.badge == "IDLE")
    }

    /// ⚠️ 這是**搬移前的行為**，不是設計過的答案：面板把在等你的 session 放在
    /// 上面另一區（`PanelView.listedSessions` 濾掉了），所以 popover 裡的
    /// `SessionRow` 不會拿到它；但 `--render-panel` 的 rows 圖用的是全部 session，
    /// 在那裡它畫成 IDLE。鎖住它是為了「行為不變」，要改請另開一件事。
    @Test("waiting 落在 IDLE（搬移前的行為）")
    func waitingFallsToIdle() {
        #expect(SessionRowStatus(session: live(.waiting(.permissionPrompt)), finish: nil) == .idle)
    }

    /// 完成標記壓過註冊表的 status —— 註冊表是黏著的（規矩 21），
    /// 講完之後好幾分鐘仍報 busy，那段時間要畫的是勾，不是 BUSY。
    @Test("有完成標記就是 finished，不管註冊表說 busy 還是 idle")
    func finishWinsOverRegistry() {
        #expect(SessionRowStatus(session: live(.busy), finish: finish) == .finished(finish))
        #expect(SessionRowStatus(session: live(.shell), finish: finish) == .finished(finish))
        #expect(SessionRowStatus(session: live(.idle), finish: finish) == .finished(finish))
        #expect(SessionRowStatus.finished(finish).badge == nil)
    }
}

@Suite("SessionElapsed —— header 右邊那個 3m")
struct SessionElapsedTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test("秒 → 分 → 時，無條件捨去（照搬 Int(...) 的截斷）")
    func units() {
        func l(_ s: TimeInterval) -> String { SessionElapsed.label(startedAt: t0, now: t0 + s) }
        #expect(l(0) == "0s")
        #expect(l(59.9) == "59s")
        #expect(l(60) == "1m")
        #expect(l(3599) == "59m")
        #expect(l(3600) == "1h")
        #expect(l(90_000) == "25h")
    }

    /// 規矩 10：`Int(Double)` 超出範圍會 trap 掉整個行程，而 `startedAt`
    /// 來自磁碟上的 JSON。搬移前是 `Int(now.timeIntervalSince(...))`，
    /// 存活判定（pid＋啟動時間 300 秒容差）實際上擋掉了荒謬的值，
    /// 但 Core 的純函式不可以依賴呼叫端替它擋。
    @Test("荒謬的時間差不 trap，畫「—」")
    func absurdIntervalDoesNotTrap() {
        #expect(SessionElapsed.label(startedAt: Date(timeIntervalSince1970: -1e300), now: t0) == "—")
        #expect(SessionElapsed.label(startedAt: t0, now: Date(timeIntervalSince1970: .infinity)) == "—")
    }
}

@Suite("ContextPressure —— ctx 細條的黃／紅門檻")
struct ContextPressureTests {

    @Test("預設門檻抄使用者狀態列腳本：70 黃、90 紅")
    func standard() {
        #expect(ContextThresholds.standard == ContextThresholds(yellow: 70, red: 90))
    }

    @Test("邊界含等號：69 綠、70 黃、89 黃、90 紅")
    func boundaries() {
        let t = ContextThresholds.standard
        #expect(ContextPressure(percent: 0, thresholds: t) == .calm)
        #expect(ContextPressure(percent: 69, thresholds: t) == .calm)
        #expect(ContextPressure(percent: 70, thresholds: t) == .warning)
        #expect(ContextPressure(percent: 89, thresholds: t) == .warning)
        #expect(ContextPressure(percent: 90, thresholds: t) == .critical)
        #expect(ContextPressure(percent: 100, thresholds: t) == .critical)
    }

    @Test("偏好覆寫：沒調過的那一格各自用預設")
    func resolvesFromPreferences() {
        #expect(ContextThresholds(Preferences.empty) == .standard)
        #expect(ContextThresholds(Preferences(contextYellow: 60, contextRed: 85))
                == ContextThresholds(yellow: 60, red: 85))
        #expect(ContextThresholds(Preferences(contextYellow: 55))
                == ContextThresholds(yellow: 55, red: 90))
        #expect(ContextThresholds(Preferences(contextRed: 95))
                == ContextThresholds(yellow: 70, red: 95))
    }
}

@Suite("ContextGauge —— ctx 那一行畫不畫、數字什麼色、窗口怎麼寫")
struct ContextGaugeTests {
    func payload(_ used: Int?, window: Int? = 200_000) -> StatusLinePayload {
        StatusLinePayload(sessionId: "s1", capturedAt: Date(timeIntervalSince1970: 0),
                          contextUsedPercent: used, contextWindowSize: window)
    }
    let t = ContextThresholds.standard

    /// 規矩 3：沒有讀數時整行不畫 —— 一條 0% 的長條看起來像「還很空」，
    /// 實際意思是「不知道」。
    @Test("沒有 payload、或 payload 沒有百分比 → nil（整行不畫）")
    func noReadingNoRow() {
        #expect(ContextGauge(nil, thresholds: t) == nil)
        #expect(ContextGauge(payload(nil), thresholds: t) == nil)
    }

    @Test("0% 是讀數，不是「不知道」")
    func zeroIsAReading() {
        let g = ContextGauge(payload(0), thresholds: t)
        #expect(g?.percent == 0)
        #expect(g?.pressure == .calm)
    }

    @Test("數字到黃門檻才跟著長條上色，以下用 secondary")
    func numberColouredFromYellow() {
        #expect(ContextGauge(payload(69), thresholds: t)?.colouredNumber == false)
        #expect(ContextGauge(payload(70), thresholds: t)?.colouredNumber == true)
        #expect(ContextGauge(payload(95), thresholds: t)?.colouredNumber == true)
    }

    @Test("窗口：≥ 1,000,000 寫 1M，其餘寫 k（無條件捨去）；沒有就不寫")
    func windowLabel() {
        #expect(ContextGauge(payload(5, window: 1_000_000), thresholds: t)?.windowLabel == "1M")
        #expect(ContextGauge(payload(5, window: 200_000), thresholds: t)?.windowLabel == "200k")
        #expect(ContextGauge(payload(5, window: 999_999), thresholds: t)?.windowLabel == "999k")
        #expect(ContextGauge(payload(5, window: nil), thresholds: t)?.windowLabel == nil)
        // `--dump` 用同一支，不是第二份寫法（規矩 48：同一段文字只能有一份實作）
        #expect(ContextGauge.windowLabel(200_000) == "200k")
    }

    /// ⚠️ 鎖住的是**搬移前**的行為，包括一個不漂亮的邊角：手改偏好檔只設
    /// `contextYellow: 95`（`sanitised()` 只在兩格都有時才檢查黃 < 紅），
    /// 解析出來是黃 95／紅 90。這時 90–94 的長條是紅的，數字卻是 secondary ——
    /// 因為數字看的是「≥ 黃」，長條看的是「≥ 紅」。搬移前就是這樣；要修請另開。
    @Test("黃 > 紅（只設一邊的手改偏好）時，數字仍然只看黃門檻")
    func invertedThresholdsKeepOldBehaviour() {
        let inverted = ContextThresholds(Preferences(contextYellow: 95))
        let g = ContextGauge(payload(92), thresholds: inverted)
        #expect(g?.pressure == .critical)
        #expect(g?.colouredNumber == false)
    }
}

/// 規矩 48 最後一條：收合那一行的用詞與顏色必須與 `WorkflowTally` 完全一樣。
/// 搬移前是 `SessionRow` 裡兩支各自 switch 的 private func，
/// 「必須一致」只是一句註解。
@Suite("TallyTone —— 收合那一行每一格的語氣")
struct TallyToneTests {

    @Test("workflow：失敗是壞消息、不明是沒有消息、其餘安靜")
    func workflow() {
        #expect(TallyTone(WorkflowTally.Outcome.completed) == .quiet)
        #expect(TallyTone(WorkflowTally.Outcome.failed) == .bad)
        #expect(TallyTone(WorkflowTally.Outcome.stopped) == .quiet)
        #expect(TallyTone(WorkflowTally.Outcome.unknown) == .unknown)
    }

    @Test("agent：nil（讀不到下場）是「狀態不明」")
    func agent() {
        #expect(TallyTone(AgentOutcome.Kind?.some(.completed)) == .quiet)
        #expect(TallyTone(AgentOutcome.Kind?.some(.failed)) == .bad)
        #expect(TallyTone(AgentOutcome.Kind?.some(.killed)) == .quiet)
        #expect(TallyTone(AgentOutcome.Kind?.none) == .unknown)
    }

    /// 兩邊用同一個字的那一格，語氣必須一樣。配對從兩個 tally 的 `collapsed`
    /// 自己的用詞取，不是在測試裡另寫一張對照表 —— 那張表會跟著實作一起錯。
    @Test("同一個字（已完成／失敗／已停止／狀態不明）在兩邊是同一個語氣")
    func sameWordSameTone() {
        let wf = WorkflowTally([
            WorkflowGroup(workflowId: "a", latestPhase: nil, agents: [], runStatus: "completed"),
            WorkflowGroup(workflowId: "b", latestPhase: nil, agents: [], runStatus: "failed"),
            WorkflowGroup(workflowId: "c", latestPhase: nil, agents: [], runStatus: "killed"),
            WorkflowGroup(workflowId: "d", latestPhase: nil, agents: [], runStatus: nil),
        ])
        func agent(_ id: String, _ o: AgentOutcome.Kind?) -> AgentNode {
            AgentNode(meta: AgentMeta(agentId: id, agentType: "general-purpose",
                                      description: "t", spawnDepth: 1),
                      runState: .finished, outcome: o)
        }
        let ag = AgentTally([agent("1", .completed), agent("2", .failed),
                             agent("3", .killed), agent("4", nil)])
        // 「1 個 workflow 已完成」「1 個失敗」→「已完成」「失敗」
        func word(_ text: String) -> String {
            let afterCount = text.split(separator: "個").last ?? ""
            return String(afterCount.split(separator: " ").last ?? "")
        }
        let wfTones = Dictionary(uniqueKeysWithValues:
            wf.collapsed.map { (word($0.text), TallyTone($0.outcome)) })
        let agTones = Dictionary(uniqueKeysWithValues:
            ag.collapsed.map { (word($0.text), TallyTone($0.outcome)) })
        #expect(Set(wfTones.keys) == Set(agTones.keys))
        #expect(wfTones.count == 4)
        for (w, tone) in wfTones { #expect(agTones[w] == tone, "「\(w)」兩邊語氣不同") }
    }
}
