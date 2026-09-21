import Testing
import Foundation
@testable import QuotaMonsterCore

/// 選單列標記「Parallax」的幾何。每個數字都來自設計規格的推導，不是估的，
/// 所以這組測試的職責就是把它們釘死 —— 之後任何人改動都必須先面對這些斷言。
///
/// 座標系：22×22pt 畫布，圓心 (11,11)，角度用數學慣例（0° = 正右，逆時針為正）。
/// 兩條弧都顯示**剩餘**額度，從 220°（左下）順時針掃過頂端，滿額時掃 260°，
/// 底部留 100° 開口。
@Suite("GlyphGeometry")
struct GlyphGeometryTests {

    /// 推導出來的半徑是浮點運算的結果（4.15 + 1.40/2 = 4.8500000000000005），
    /// 所以比較要帶容差。這是測試該負的責任，不是實作。
    func near(_ a: CGFloat, _ b: CGFloat, _ tol: CGFloat = 0.000_001) -> Bool { abs(a - b) < tol }

    // ── 半徑預算（8.00pt 由內而外分完）────────────────────────
    @Test("半徑預算加起來剛好是 16pt 的墨水")
    func radialBudgetSumsTo16ptOfInk() {
        let g = GlyphGeometry.self
        #expect(near(g.creatureEnvelopeRadius, 2.148))
        #expect(near(g.innerArc.innerEdge, 3.45))
        #expect(near(g.innerArc.outerEdge, 4.85))
        #expect(near(g.outerArc.innerEdge, 6.50))
        #expect(near(g.outerArc.outerEdge, 8.00))
        #expect(near(g.outerArc.outerEdge * 2, 16.0))
    }

    @Test("外弧比內弧粗 —— 5 小時窗口動得快，需要更重的筆畫")
    func outerStrokeIsHeavierThanInner() {
        #expect(GlyphGeometry.outerArc.stroke == 1.50)
        #expect(GlyphGeometry.innerArc.stroke == 1.40)
    }

    @Test("兩個 counter 都低於 1x 下限 —— 這是刻意的取捨，必須被記錄下來")
    func bothCountersAreKnowinglyBelowTheOnePixelFloor() {
        // 換來的是一隻 4.10pt 寬、撐得住姿態的生物。
        // 若堅持 2.0pt counter，生物只剩約 1.2pt，是一個斑點。
        #expect(GlyphGeometry.counterA < 2.0)
        #expect(GlyphGeometry.counterB < 2.0)
        #expect(GlyphGeometry.counterA > 1.0)   // 2x 下仍然清楚
        #expect(GlyphGeometry.counterB > 1.0)
    }

    // ── 量表弧 ────────────────────────────────────────────────
    @Test("滿額時掃 260°，底部留 100° 開口")
    func fullGaugeSweeps260Degrees() {
        let a = GlyphGeometry.gaugeArc(remaining: 1.0)
        #expect(a.start == 220.0)
        #expect(abs(a.end - (-40.0)) < 0.001)
        #expect(abs(a.sweep - 260.0) < 0.001)
    }

    @Test("額度耗盡時弧長歸零，但軌道還在")
    func emptyGaugeHasNoSweep() {
        #expect(GlyphGeometry.gaugeArc(remaining: 0).sweep == 0)
    }

    @Test("剩 50% 時弧正好停在頂端 —— 這就是 50% 標記的位置")
    func halfRemainingEndsAtTopDeadCentre() {
        let a = GlyphGeometry.gaugeArc(remaining: 0.5)
        #expect(abs(a.end - GlyphGeometry.halfMarkAngle) < 0.001)
    }

    @Test("50% 標記固定在正上方")
    func halfMarkSitsAtTopDeadCentre() {
        #expect(GlyphGeometry.halfMarkAngle == 90.0)
    }

    @Test("50% 圓點的直徑等於該條弧的筆寬，所以兩邊都不凸出")
    func halfMarkDiscMatchesItsBandWidth() {
        #expect(GlyphGeometry.outerArc.halfMarkDiameter == GlyphGeometry.outerArc.stroke)
        #expect(GlyphGeometry.innerArc.halfMarkDiameter == GlyphGeometry.innerArc.stroke)
    }

    // ── agent 數 ──────────────────────────────────────────────
    @Test("沒有 agent 時只有暗軌，軌道在每個狀態都存在")
    func zeroAgentsLeavesOnlyTheDimRail() {
        #expect(GlyphGeometry.agentUnits(count: 0) == .none)
    }

    @Test("一隻 agent 落在正下方")
    func oneAgentSitsAtBottomDeadCentre() {
        #expect(GlyphGeometry.agentUnits(count: 1) == .discrete([-90.0]))
    }

    @Test("兩隻與三隻的角度都是推導出來的固定值")
    func twoAndThreeAgentsUseDerivedAngles() {
        #expect(GlyphGeometry.agentUnits(count: 2) == .discrete([-103.968, -76.032]))
        #expect(GlyphGeometry.agentUnits(count: 3) == .discrete([-109.857, -90.0, -70.143]))
    }

    @Test("四隻以上合併成一條滿軌的橫槓 —— 精度到此為止，且必須誠實")
    func fourOrMoreMergesIntoOneBar() {
        #expect(GlyphGeometry.agentUnits(count: 4) == .merged)
        #expect(GlyphGeometry.agentUnits(count: 15) == .merged)
    }

    @Test("agent 軌道完全落在底部開口內，永遠碰不到弧的端帽")
    func agentRailStaysInsideTheOpening() {
        let rail = GlyphGeometry.agentRail
        #expect(abs(rail.sweep - 44.7) < 0.01)
        #expect(rail.start < -67.0 && rail.start > -68.0)
        #expect(rail.end > -113.0 && rail.end < -112.0)
    }

    // ── 阻塞分段 ──────────────────────────────────────────────
    @Test("一個阻塞是完整的閉環，不切")
    func oneBlockedIsAContinuousRing() {
        #expect(GlyphGeometry.alertSegments(blocked: 1) == .closedRing)
    }

    @Test("N 個阻塞切成 N 等份，間隙固定 27.936°")
    func nBlockedCutsIntoNEqualParts() {
        guard case .segments(let s) = GlyphGeometry.alertSegments(blocked: 3) else {
            Issue.record("expected segments"); return
        }
        #expect(s.count == 3)
        #expect(abs(s[0].sweep - 92.064) < 0.001)
        // 每一段加上一個間隙，總和必須是整圈
        #expect(abs(Double(s.count) * (s[0].sweep + GlyphGeometry.alertGapDegrees) - 360.0) < 0.001)
    }

    @Test("上限是 6 —— 再多段就讀成虛線而不是分段")
    func segmentCeilingIsSix() {
        guard case .segments(let six) = GlyphGeometry.alertSegments(blocked: 6),
              case .segments(let ten) = GlyphGeometry.alertSegments(blocked: 10) else {
            Issue.record("expected segments"); return
        }
        #expect(six.count == 6)
        #expect(ten.count == 6)   // 超過就停在 6，確切數字交給面板
    }

    @Test("分段的相位由奇偶決定，正上方永遠是確定的地標")
    func segmentPhaseDependsOnParity() {
        // 偶數：段落置中於正上方；奇數：間隙置中於正上方
        guard case .segments(let even) = GlyphGeometry.alertSegments(blocked: 2),
              case .segments(let odd) = GlyphGeometry.alertSegments(blocked: 3) else {
            Issue.record("expected segments"); return
        }
        #expect(even.contains { $0.contains(GlyphGeometry.halfMarkAngle) })
        #expect(odd.contains { $0.contains(GlyphGeometry.halfMarkAngle) } == false)
    }

    // ── 生物 ──────────────────────────────────────────────────
    @Test("生物的動作分三段，由 agent 數決定")
    func creaturePostureFollowsAgentCount() {
        #expect(GlyphGeometry.creaturePosture(agents: 0) == .still)
        #expect(GlyphGeometry.creaturePosture(agents: 1) == .awake)
        #expect(GlyphGeometry.creaturePosture(agents: 3) == .awake)
        #expect(GlyphGeometry.creaturePosture(agents: 4) == .driving)
    }

    @Test("額度耗盡時生物睡著，壓過任何 agent 數")
    func exhaustedQuotaPutsTheCreatureToSleep() {
        #expect(GlyphGeometry.creaturePosture(agents: 9, exhausted: true) == .asleep)
    }

    @Test("傾斜 5° 時生物仍與內弧保持 1.19pt 淨空 —— 6° 就會吃進去")
    func leanKeepsClearanceFromTheInnerArc() {
        let clearance = GlyphGeometry.innerArc.innerEdge - GlyphGeometry.leanedEnvelopeRadius
        #expect(near(clearance, 1.187, 0.01))
    }
}
