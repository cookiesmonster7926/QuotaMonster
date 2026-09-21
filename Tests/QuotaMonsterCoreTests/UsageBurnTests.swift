import Testing
import Foundation
@testable import QuotaMonsterCore

/// 「最近的節奏有多快」。
///
/// **這一整個型別的存在理由，是額度曲線裡的四個性質。**
/// 每一個都對著 `Fixtures/usage/history-8h.jsonl` 的位元組測 ——
/// 一份順順地爬上去的乾淨資料會把那些性質整理掉，而它們正是難的地方。
///
///   1. 5 小時序列是鋸齒：`24 → null → 1`、`7 → null → 0`
///   2. 窗口內不單調：`+3690…+3735` 的 `19, 18, 19, 18, 19`，跨度 45 秒
///   3. null 出現在序列**中間**（30 筆裡 2 筆，其中 `+25590` 夾在 4 與 5 之間）
///   4. 空隙有歧義：`+12003 → +24410` 之間 3 小時 27 分沒有任何一行
///
/// ### fixture 的來源〔這一段是事實陳述，不是量測〕
/// 這份 fixture 是**合成的**，不是任何一次真實擷取。它是照上面四個性質
/// 手工鋪出來的：時間基準取 `1_800_000_000` 這個整數，所有的點都寫成
/// 它的偏移量；數值曲線重畫過，只保留形狀。
///
/// ⚠️ **所以底下每一個釘死的期望值都是「這份合成資料上的計算結果」，
/// 不是對真實世界的量測。** 它們是用一份獨立於 `UsageBurn.swift` 重寫的
/// Theil–Sen 參考實作推出來的（先拿舊的真實 fixture 驗過那份參考實作
/// 能重現舊的期望值），所以「Swift 與參考實作同意」這件事有意義；
/// 但「真實的 Claude Code 會長這樣」這件事，證據不在這個 repo 裡。
///
/// ⚠️ `UsageBurn.swift` / `UsageProjection.swift` 的註解裡還留著幾個標成
/// 〔實測〕的數字（817/2646 秒、22.52 pp/h……）。那些是對**已經移除的**
/// 真實擷取做的量測，仍然是量測，但這個 repo 裡已經沒有可以重跑的證據了。
/// 不要把它們跟底下這些合成資料的數字混在一起看。
@Suite("UsageBurn")
struct UsageBurnTests {

    /// 合成時間基準。fixture 裡每一行都是 `base + 偏移`。
    static let base = 1_800_000_000
    /// 把偏移量寫成日期。測試裡一律用偏移量講話 ——
    /// 絕對 epoch 在這份合成資料上不代表任何東西。
    static func at(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(base + offset))
    }
    func at(_ offset: Int) -> Date { Self.at(offset) }

    /// fixture 最後一個點（`+34000`）。
    var end: Date { at(34_000) }

    func samples() throws -> [UsageSample] {
        let url = try Fixture.url("usage/history-8h.jsonl")
        return UsageHistory().read(url, now: end)
    }

    /// 第一個窗口的起點，早於整份 fixture 的第一行。
    var firstWindowStart: Date { at(-7_200) }
    /// 第二個窗口的起點：`+10800` 那次重置。
    var secondWindowStart: Date { at(10_800) }
    /// 第三個窗口的起點：`+28800` 那次重置。
    var thirdWindowStart: Date { at(28_800) }

    // ── 四個性質 ───────────────────────────────────────────────

    @Test("鋸齒靠 windowStart 在結構上擋掉 —— 不是靠偵測重置")
    func theSawtoothIsCutByTheWindowStartNotDetected() throws {
        // 第二個窗口從 +10800 開始，所以 +4530 那個 24 進不來。
        // 偵測「值下降就是重置」會在 19→18 那種來源振盪上誤判；
        // windowStart 是算出來的（resetsAt − 窗口長度），不會誤判。
        let run = UsageBurn.recentRun(try samples(), window: \.fiveHour,
                                      windowStart: secondWindowStart,
                                      now: at(12_500))
        #expect(run.allSatisfy { $0.value <= 2 })
        #expect(!run.contains { $0.value == 24 })
    }

    @Test("null 是洞，不是 0，也不是切口 —— 序列跨過它")
    func nullIsAHoleNotAZero() throws {
        // `+25590` 的 5h=null 夾在 4 與 5 之間，兩側的間隔都小於 maximumGap。
        // 把它當 0 會造出一個憑空的下降；把它當切口會在任何一次讀取失敗時
        // 把序列砍成兩半。它只是被跳過 —— 所以 7 個點，而且頭還在洞的前面。
        let run = UsageBurn.recentRun(try samples(), window: \.fiveHour,
                                      windowStart: secondWindowStart,
                                      now: at(25_950))
        #expect(run.count == 7)
        #expect(run.first?.at == at(24_410))
        #expect(!run.contains { $0.value == 0 })
        #expect(!run.contains { $0.at == at(25_590) })
    }

    @Test("3 小時 27 分的空隙把序列切斷，不是橋接過去")
    func theLongGapCutsTheRun() throws {
        // `+12003` 到 `+24410` 之間一行都沒有。那可能是「數字沒變」，
        // 也可能是「app 沒開」—— 檔案裡分不出來。所以不橋接。
        let run = UsageBurn.recentRun(try samples(), window: \.fiveHour,
                                      windowStart: secondWindowStart, now: at(25_950))
        #expect(run.first?.at == at(24_410))
        #expect(!run.contains { $0.at <= at(12_003) })
    }

    @Test("尾巴太舊就拒絕 —— 二十分鐘前的節奏不是「最近」")
    func aStaleTailRefuses() throws {
        let hourLater = end.addingTimeInterval(3600)
        let outcome = UsageBurn.fiveHour(try samples(), windowStart: thirdWindowStart,
                                         now: hourLater)
        guard case .refused(let why) = outcome else {
            Issue.record("應該拒絕，卻給了估計"); return
        }
        if case .staleTail = why {} else { Issue.record("拒絕的理由不對：\(why)") }
    }

    // ── 抗噪：這一個常數就是全部的抗噪能力 ───────────────────────

    @Test("那五個振盪點連一對都湊不出來 —— 最小配對間隔 180 秒全部擋掉")
    func theOscillationYieldsNoPairsAtAll() throws {
        let osc = try oscillation()
        #expect(osc.count == 5)
        #expect(osc.last!.at.timeIntervalSince(osc.first!.at) == 45)
        #expect(UsageBurn.theilSen(osc,
                                   minimumPairInterval: UsageBurn.fiveHourMinimumPairInterval)
                == nil)
    }

    @Test("對照組：最小平方法在同一組點上會說「燒量是負的」")
    func ordinaryLeastSquaresGoesNegativeOnTheSamePoints() throws {
        // 這個測試存在的唯一目的，是擋住有人把 Theil–Sen「簡化」成線性回歸。
        // 同一組點，OLS 的斜率是 −8.1238 pp/h —— 一個會顯示在面板上的負燒量。
        let osc = try oscillation()
        #expect(abs(Self.ols(osc) - (-8.1238)) < 0.001)
        #expect(Self.ols(osc) < 0)
    }

    @Test("對照組：拿掉最小配對間隔，Theil–Sen 自己也撐不住")
    func theilSenWithoutTheMinimumIntervalIsUseless() throws {
        // 中位數會是 0，而四分位距是 ±64.2857 pp/h —— 抗噪能力全部來自
        // 那個間隔，不是來自中位數本身。
        let s = try #require(UsageBurn.theilSen(try oscillation(), minimumPairInterval: 0))
        #expect(abs(s.median) < 1e-9)
        #expect(abs(s.lowerQuartile - (-64.2857)) < 0.001)
        #expect(abs(s.upperQuartile - 64.2857) < 0.001)
    }

    @Test("那段突發：中位數 22.19 pp/h，六對")
    func theBurst() throws {
        // `+3690…+4530` 的七個點，包含整段振盪。七個點卻只有六對 ——
        // 前五個擠在 45 秒內，湊不出任何一對隔得夠遠的。
        let all = try samples()
        let burst = UsageBurn.recentRun(all, window: \.fiveHour,
                                        windowStart: firstWindowStart,
                                        now: at(4_530))
            .filter { $0.at >= at(3_690) }
        #expect(burst.count == 7)
        let s = try #require(UsageBurn.theilSen(
            burst, minimumPairInterval: UsageBurn.fiveHourMinimumPairInterval))
        #expect(s.pairCount == 6)
        #expect(abs(s.median - 22.1903) < 0.001)
        #expect(abs(s.lowerQuartile - 21.5542) < 0.001)
        #expect(abs(s.upperQuartile - 25.0152) < 0.001)
    }

    // ── 具名的拒絕 ─────────────────────────────────────────────

    @Test("空的歷史拒絕，而且說得出理由")
    func emptyHistoryRefusesByName() {
        guard case .refused(let why) = UsageBurn.fiveHour([], windowStart: secondWindowStart,
                                                          now: end) else {
            Issue.record("應該拒絕"); return
        }
        #expect(why == .noSamples)
    }

    @Test("+1800 那一刻只湊得出五對 —— 差一對，拒絕")
    func fivePairsIsNotEnough() throws {
        // 門檻是六對。四個點本來有六對，但頭兩個只差 170 秒 ——
        // 差一對，所以這是最好的邊界測試。
        let outcome = UsageBurn.fiveHour(try samples(), windowStart: firstWindowStart,
                                         now: at(1_800))
        guard case .refused(let why) = outcome else {
            Issue.record("應該拒絕，卻給了估計"); return
        }
        #expect(why == .tooFewPairs(5))
    }

    @Test("+2580 那一刻剛好湊得出九對 —— 過了，中位數 8.5714")
    func ninePairsSpeaks() throws {
        let outcome = UsageBurn.fiveHour(try samples(), windowStart: firstWindowStart,
                                         now: at(2_580))
        let e = try #require(outcome.value)
        #expect(e.pairCount == 9)
        #expect(abs(e.percentPerHour - 8.5714) < 0.001)
    }

    @Test("+4530 那一刻：14 個點、74 對、中位數 8.8134")
    func theLongestRunInTheFile() throws {
        let outcome = UsageBurn.fiveHour(try samples(), windowStart: firstWindowStart,
                                         now: at(4_530))
        let e = try #require(outcome.value)
        #expect(e.sampleCount == 14)
        #expect(e.pairCount == 74)
        #expect(abs(e.percentPerHour - 8.8134) < 0.001)
        #expect(abs(e.lowerPercentPerHour - 7.0822) < 0.001)
        #expect(abs(e.upperPercentPerHour - 10.4662) < 0.001)
    }

    @Test("+25950 那一刻：最近 10.74 pp/h —— 而那個窗口的均速只有 1.66")
    func theCaseThatJustifiesAdmittingHistoryAtAll() throws {
        // 這個窗口的均速被裡面那段 3.4 小時的閒置壓到 1.66 pp/h，
        // 但你當下其實在以 10.74 燒。這一個點就是「為什麼要看歷史」的全部理由。
        // （均速那一半在 UsageOutlookTests.theFasterCase 裡驗。）
        let outcome = UsageBurn.fiveHour(try samples(), windowStart: secondWindowStart,
                                         now: at(25_950))
        let e = try #require(outcome.value)
        #expect(e.sampleCount == 7)
        #expect(abs(e.percentPerHour - 10.7380) < 0.001)
    }

    // ── 整份重播：永遠不准出現負燒量 ────────────────────────────

    @Test("走過檔案的每一個點，沒有任何一步算出負的燒量")
    func replayingTheWholeFileNeverGoesNegative() throws {
        let all = try samples()
        for s in all where s.fiveHour != nil {
            // 三個窗口都試一遍，因為真實的 windowStart 會隨時間換。
            for start in [firstWindowStart, secondWindowStart, thirdWindowStart] {
                if let e = UsageBurn.fiveHour(all, windowStart: start, now: s.at).value {
                    #expect(e.percentPerHour >= 0)
                    #expect(e.lowerPercentPerHour > 0)
                }
            }
        }
    }

    // ── helper ────────────────────────────────────────────────

    /// `+3690…+3735` 的五個點：`19, 18, 19, 18, 19`，跨度 45 秒。
    func oscillation() throws -> [BurnPoint] {
        try samples()
            .filter { $0.at >= at(3_690) && $0.at <= at(3_735) }
            .compactMap { s in s.fiveHour.map { BurnPoint(at: s.at, value: $0) } }
    }

    /// 測試自己帶的最小平方法，只用來當對照組。
    static func ols(_ points: [BurnPoint]) -> Double {
        let n = Double(points.count)
        let mt = points.reduce(0.0) { $0 + $1.at.timeIntervalSince1970 } / n
        let mv = points.reduce(0.0) { $0 + Double($1.value) } / n
        let num = points.reduce(0.0) {
            $0 + ($1.at.timeIntervalSince1970 - mt) * (Double($1.value) - mv)
        }
        let den = points.reduce(0.0) { $0 + pow($1.at.timeIntervalSince1970 - mt, 2) }
        return num / den * 3600
    }
}
