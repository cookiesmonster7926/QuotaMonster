import Testing
import Foundation
@testable import QuotaMonsterCore

@Suite("GlyphState")
struct GlyphStateTests {

    func usage(five: Int?, seven: Int?, freshness: Freshness = .live) -> UsageSnapshot {
        UsageSnapshot(fiveHour: five.map { UsageWindow(percent: $0, resetsAt: nil) },
                      sevenDay: seven.map { UsageWindow(percent: $0, resetsAt: nil) },
                      perModel: [:], freshness: freshness,
                      fetchedAt: Date(timeIntervalSince1970: 0))
    }

    func session(_ status: SessionStatus) -> LiveSession {
        LiveSession(session: ClaudeSession(pid: 1, sessionId: "s", cwd: "/tmp/p",
                                           startedAt: Date(), status: status))
    }

    @Test("已使用百分比換算成剩餘比例")
    func usedPercentBecomesRemainingFraction() {
        let s = GlyphState.from(usage: usage(five: 28, seven: 18), sessions: [], runningAgents: 0, thresholds: .standard)
        #expect(abs((s.fiveHourRemaining ?? 0) - 0.72) < 0.0001)
        #expect(abs((s.sevenDayRemaining ?? 0) - 0.82) < 0.0001)
    }

    @Test("沒有讀數時是 nil，不是 0 —— 空的量表與滿的量表必須不同")
    func missingReadingIsNilNotZero() {
        let s = GlyphState.from(usage: usage(five: 28, seven: nil), sessions: [], runningAgents: 0, thresholds: .standard)
        #expect(s.sevenDayRemaining == nil)
    }

    @Test("完全沒有 usage 時新鮮度視為過期")
    func absentUsageIsTreatedAsExpired() {
        let s = GlyphState.from(usage: nil, sessions: [], runningAgents: 0, thresholds: .standard)
        #expect(s.freshness == .expired)
    }

    @Test("有人在等你就進入警示，而且那是唯一會用到顏色的狀態")
    func blockedSessionTriggersTheOnlyColouredState() {
        let s = GlyphState.from(usage: usage(five: 28, seven: 18),
                                sessions: [session(.waiting(.permissionPrompt))], runningAgents: 3, thresholds: .standard)
        #expect(s.isAlerting == true)
        #expect(s.usesTemplateRendering == false)
    }

    // ⚠️ 顏色政策在 2026-09-18 下午改過。
    // 舊規則：顏色專屬於「有人在等你」，其他一律 template（這條測試原本釘的就是它）。
    // 新規則（使用者要求）：平常依剩餘額度上色，**只有沒有可信讀數時**才走 template。
    // 警示狀態不靠顏色區分 —— 它是完全不同的形狀，而且是唯一會呼吸的。

    @Test("有可信讀數時就上色，不再走 template")
    func readableStatesAreColoured() {
        let s = GlyphState.from(usage: usage(five: 95, seven: 99),
                                sessions: [session(.busy)], runningAgents: 9, thresholds: .standard)
        #expect(s.quotaTier == .critical)          // 剩 5% / 1%
        #expect(s.usesTemplateRendering == false)
    }

    @Test("完全沒有讀數時仍然走 template —— 對不知道的值上色是說謊")
    func unknownStaysTemplate() {
        let s = GlyphState.from(usage: nil, sessions: [session(.busy)], runningAgents: 9, thresholds: .standard)
        #expect(s.quotaTier == nil)
        #expect(s.usesTemplateRendering == true)
    }

    @Test("任一窗口歸零就是耗盡，生物睡著")
    func eitherWindowAtZeroMeansExhausted() {
        let s = GlyphState.from(usage: usage(five: 100, seven: 18), sessions: [], runningAgents: 5, thresholds: .standard)
        #expect(s.exhausted == true)
        #expect(s.posture == .asleep)
    }

    @Test("agent 數決定姿態")
    func agentCountDrivesPosture() {
        func posture(_ n: Int) -> GlyphGeometry.CreaturePosture {
            GlyphState.from(usage: usage(five: 28, seven: 18), sessions: [], runningAgents: n, thresholds: .standard).posture
        }
        #expect(posture(0) == .still)
        #expect(posture(2) == .awake)
        #expect(posture(7) == .driving)
    }
}
