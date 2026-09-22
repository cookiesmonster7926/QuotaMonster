import SwiftUI
import AppKit
import QuotaMonsterCore

/// 簡易版面（使用者 2026-09-22 從三個候選裡選的「A 放大鏡」）。
///
/// 一句話：**選單列那顆標記的 6× 版，連它在有人等你時會整顆變琥珀環都照樣。**
///
/// ### 它回答哪一個問題
/// 「我還有多少額度」。完整版回答的是「每一個 session 現在怎麼了」——
/// 兩者不是同一頁的兩種皮，所以這裡**不放** session 逐列、每日圖表、分模型第三欄。
///
/// ### ⚠️ 有人在等你的時候，兩條額度弧會消失
/// 那不是這個檔案的設計，是 `GlyphRenderer` 今天的行為：`isAlerting` 時直接分流到
/// `drawAlert`，`drawGauges` 完全不跑。**這是這個版面願意付的代價** ——
/// 那一刻額度資訊由右邊兩個數字承擔（它們不受影響）。
/// ⚠️ **不要補救。** 要補救就得在 App 層合成一個 `blockedSessions: 0` 的假狀態，
/// 那是規矩 4（決策只能放 Core），也會打破「琥珀與丁香紫在型別上不可同時出現」。
struct SimplePanelBody: View {

    @Bindable var store: DataStore
    let onDark: Bool

    /// 標記畫多大。⚠️ 這是版面常數不是門檻 —— 它唯一的影響是好不好看。
    private static let glyphSide: CGFloat = 132

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                BigGlyph(state: store.glyph, side: Self.glyphSide,
                         ink: onDark ? .white : .black)
                VStack(alignment: .leading, spacing: 12) {
                    readout("5 小時視窗 · 已用", store.usage?.fiveHour, store.glyph.fiveHourTier)
                    Rectangle().fill(.quaternary).frame(height: 0.5)
                    readout("7 天 · 全模型 · 已用", store.usage?.sevenDay, store.glyph.sevenDayTier)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 8)

            HStack {
                Spacer()
                Text(freshnessText).font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16).padding(.bottom, 10)

            // 沒裝 tee 的話，這一頁也要說得出原因 —— 判斷在 Core，這裡只畫。
            if let hint = UsageSourceCaption.setupHint(
                usage: store.usage, source: store.usageSource,
                statusLinePayloadCount: store.statusLinePayloadCount,
                installCommand: store.installCommand) {
                Text(hint)
                    .font(.system(size: 9.5)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(.horizontal, 16).padding(.bottom, 10)
            }

            Divider().opacity(0.5)
            activity
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.vertical, 11)
        }
    }

    // ── 讀數 ───────────────────────────────────────────────────

    /// ⚠️ **數字印的是「已用」**，與 `PanelView.cell` 同一個 `w.percent`、
    /// 同一套語彙（規矩 43）。而弧畫的是**剩餘** —— 這裡刻意**不加圖例**解釋這件事：
    /// 一個號稱「基礎資訊就好」的頁面，唯一的新文案不該是在解釋主角圖為什麼不能直接讀。
    /// 所以標籤上寫「已用」兩個字，讓數字自己說清楚它是哪一個方向。
    ///
    /// ⚠️ **顏色取自 tier、值取自 usage，兩者必須分開。**
    /// `tier(of:)` 在 `freshness == .expired` 時回 nil，而 `usage.fiveHour.percent` 還在 ——
    /// 過期時是「數字照印、不上色、整區 `opacity(0.5)`」（＝完整面板今天的行為），
    /// **不是畫「—」**。「—」只保留給 usage 真的沒有那個窗口。
    /// 那是規矩 1 的兩層：看到它但它舊了 ≠ 整個沒看到它。
    private func readout(_ title: String, _ w: UsageWindow?, _ tier: QuotaTier?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(w.map { "\($0.percent)" } ?? "—")
                    .font(.system(size: 34, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tier.map { Color(QuotaPalette.nsColor($0, onDark: onDark)) }
                                     ?? Color.primary)
                if w != nil {
                    Text("%").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                }
            }
            Text(resetText(w)).font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1)
        }
        .opacity(store.usage?.freshness == .expired ? 0.5 : 1)
    }

    // ── session 的「另一種形式」───────────────────────────────

    /// ⚠️ **修飾語換載體，但不可以消失。**
    /// 完整面板用 `SessionRow` 那顆 `opacity(0.45)` 的點說「這隻 agent 是推定的」；
    /// 這一頁沒有那顆點，所以改用文字 —— 措辭逐字沿用 `Dump.swift` 的
    /// 「（其中 N 隻是由 transcript 活動推定的）」。
    /// 一個把「推定」悄悄變成斷言的簡易頁，比沒有簡易頁更糟。
    private var activity: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(sessionLine).font(.system(size: 13, weight: .medium))
            Text(agentLine).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private var sessionLine: String {
        var running = 0, idle = 0, waiting = 0
        for s in store.sessions {
            if s.needsHuman { waiting += 1 } else if s.isWorking { running += 1 } else { idle += 1 }
        }
        return "\(store.sessions.count) 個 session · \(running) 執行 · \(idle) 閒置 · \(waiting) 等待"
    }

    private var agentLine: String {
        let total = store.runningAgents
        guard total > 0 else { return "沒有 agent 在跑" }
        let likely = store.trees.values.reduce(0) { $0 + $1.likelyRunningAgentCount }
        return likely > 0
            ? "\(total) 隻 agent 在跑（其中 \(likely) 隻是由 transcript 活動推定的）"
            : "\(total) 隻 agent 在跑"
    }

    // ── 小工具 ─────────────────────────────────────────────────

    private var freshnessText: String {
        guard let u = store.usage else { return "沒有讀數" }
        switch u.freshness {
        case .live:          return "剛更新"
        case .aging(let m):  return "\(m) 分鐘前"
        case .expired:       return "讀數已過期"
        }
    }

    /// 沒有重置時間就畫「—」，不要畫「剩 0m」。
    private func resetText(_ w: UsageWindow?) -> String {
        guard let r = w?.resetsAt else { return "—" }
        let mins = Int(r.timeIntervalSince(store.lastRefresh) / 60)
        guard mins > 0 else { return "重置時間已過" }
        return mins >= 60 ? "剩 \(mins / 60)h \(mins % 60)m" : "剩 \(mins)m"
    }
}

/// 放大的選單列標記。
///
/// ### ⚠️ 一定要包一層新的 `NSImage` 重畫，不可以 `Image(nsImage:).resizable()`
/// 〔實測 2026-09-22〕在 `ImageRenderer(scale: 2)`、132pt 目標下沿中線掃描：
/// `.resizable()` 有 **24 個過渡像素**（邊緣糊掉），包裝重畫是 **0 個**。
///
/// 更嚴重的是顏色：來源若 `isTemplate == true`，SwiftUI 會用 `foregroundStyle`
/// 把兩條弧的顏色**整個吃掉**（實測紅／藍變成一片單色）。
/// 而 `GlyphState.usesTemplateRendering` 在「沒有讀數／過期」時正好是 true ——
/// **這個陷阱剛好落在最需要誠實的那一格**。包裝之後 `isTemplate == false`，顏色原封不動。
///
/// ⚠️ 也不可以改用 `IconRenderer`。它畫的是 app 圖示：`innerLitFraction` 寫死、
/// 永遠畫一隻 agent、用自己的 hex 三元組而不是 `QuotaPalette`，檔頭自己寫著
/// 「不是某個當下的讀數」。拿它當主角＝在使用者找真讀數的地方畫一個很像真的假讀數。
struct BigGlyph: View {
    let state: GlyphState
    let side: CGFloat
    let ink: NSColor

    var body: some View {
        Image(nsImage: enlarged).frame(width: side, height: side)
    }

    /// 出貨的那顆 renderer，畫進一個大的畫布。**不是第二份畫法。**
    var enlarged: NSImage {
        let source = GlyphRenderer.image(for: state, ink: ink)
        return NSImage(size: NSSize(width: side, height: side), flipped: false) { r in
            source.draw(in: r)
            return true
        }
    }
}
