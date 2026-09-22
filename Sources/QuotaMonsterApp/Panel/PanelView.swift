import SwiftUI
import QuotaMonsterCore

/// 下拉面板。
///
/// 結構是先前定案的「釘住 + 捲動」：表頭、額度、阻塞卡**永遠可見**，
/// 只有其餘的 session 清單捲動。這樣第五個 session 出現時面板高度不會爆掉。
struct PanelView: View {
    @Bindable var store: DataStore

    /// 開機自動啟動現在是什麼狀態。
    ///
    /// ⚠️ 放 `@State` 而不是每次重繪都問 `SMAppService` —— 那是一次跨行程查詢，
    /// 而這個面板每 3 秒重畫一次。
    @State private var loginItem = LoginItem.state

    /// 由 `StatusItemController` 注入 —— 面板自己不開視窗。
    /// ⚠️ 面板是 `.transient` 的 `NSPopover`，開一扇視窗的那一下很可能讓它自己
    /// 關掉。**這一條是推論，沒有實機驗證** —— 所以收起 popover 的動作交給
    /// 注入端做，這裡只負責說「使用者按了」。
    var openPreferences: (() -> Void)?

    /// 面板背景是深色還是淺色。進度條的色階要照這個分兩組，
    /// 否則同一組色值在其中一邊一定偏悶或偏亮。
    @Environment(\.colorScheme) private var colorScheme
    private var onDark: Bool { colorScheme == .dark }

    private let width: CGFloat = 380

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            quota
            Divider().opacity(0.5)
            blockedBanner
            sessionList
            Divider().opacity(0.5)
            footer
        }
        .frame(width: width)
        .task { store.refresh() }
    }

    // ── 表頭 ───────────────────────────────────────────────────

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("QuotaMonster").font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 8)
            stat("\(store.summary.total)", "SESSIONS")
            stat("\(store.runningAgents)", "AGENTS")
            stat("\(store.summary.blocked)", "BLOCKED",
                 highlighted: store.summary.blocked > 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }

    private func stat(_ value: String, _ label: String, highlighted: Bool = false) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(highlighted ? Color.orange : .primary)
            Text(label)
                .font(.system(size: 8.5, weight: .medium))
                .tracking(0.6)
                .foregroundStyle(.tertiary)
        }
        .frame(minWidth: 46)
        .padding(.vertical, 3)
        .background {
            if highlighted {
                RoundedRectangle(cornerRadius: 5).fill(Color.orange.opacity(0.16))
            }
        }
    }

    // ── 額度 ───────────────────────────────────────────────────

    private var quota: some View {
        VStack(spacing: 9) {
            HStack {
                Text("額度 QUOTA").sectionLabel()
                Spacer()
                Text(freshnessText).font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            HStack(spacing: 0) {
                cell("5 小時視窗", store.usage?.fiveHour, caption: fiveHourCaption)
                    .help(OutlookCaption.evidence(fiveHourOutlook))
                divider
                cell("7 天 · 全模型", store.usage?.sevenDay, caption: sevenDayCaption)
                    .help(OutlookCaption.evidence(sevenDayOutlook))
                divider
                perModelCell
            }
            // ⚠️ 新使用者第一眼看到的就是這個。
            // 〔實測 2026-09-21〕`~/.claude.json` 那個來源已經不再更新
            //（檔案一直被重寫，但 fetchedAtMs 凍了 3.9 天），所以沒裝 tee
            // 三欄全是「—」。只給一個「無讀數」會讓人以為 app 壞了。
            // ⚠️ 「該不該出現」的判斷在 Core（有測試釘住「tee 有在寫就不准說沒裝」），
            // 這裡只負責畫。
            if let hint = UsageSourceCaption.setupHint(
                usage: store.usage, source: store.usageSource,
                statusLinePayloadCount: store.statusLinePayloadCount) {
                Text(hint)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)   // 指令要能複製走
            }
            // 每日長條圖。⚠️ 沒有 7 天窗口的重置時間就**整個不畫** ——
            // 那不是「七根都是 0%」，是「這張圖畫不出來」（規矩 2）。
            if let bars = store.dailyBars {
                Divider().opacity(0.4).padding(.vertical, 1)
                DailyBarChart(bars: bars)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        // ⚠️ 沒有這一行，額度區塊會被撐高。
        // 裡面的直線是 Rectangle，垂直方向是貪婪的（有多少吃多少），
        // 所以只要外層給的高度大於內容，它就會把整個區塊拉長，
        // 三欄數字被擠到中間、上下各留一大片空白。實測 173pt 裝 ~100pt 的內容。
        .fixedSize(horizontal: false, vertical: true)
    }

    private var divider: some View {
        Rectangle().fill(.quaternary).frame(width: 0.5).padding(.vertical, 2)
    }

    /// 5 小時那一欄的註腳：倒數 + 照均速的重置時投射。
    ///
    /// 這一欄在此之前從來沒有 caption，一直是走 `resetText(w)` 的預設。
    /// 投射說不出話時（例如窗口才剛重置 45 分鐘內），字串會**一個位元組不差地**
    /// 回到那個預設 —— 有測試釘住。
    private var fiveHourOutlook: UsageOutlook? {
        guard let u = store.usage else { return nil }
        // measuredAt 是讀數被抓下來的那一刻，不是現在。見 UsageProjection。
        return UsageOutlook.fiveHour(u.fiveHour, freshness: u.freshness,
                                     measuredAt: u.fetchedAt, samples: store.recentSamples)
    }

    private var sevenDayOutlook: UsageOutlook? {
        guard let u = store.usage else { return nil }
        return UsageOutlook.sevenDay(u.sevenDay, freshness: u.freshness,
                                     measuredAt: u.fetchedAt)
    }

    private var fiveHourCaption: String {
        OutlookCaption.fiveHour(resetText: resetText(store.usage?.fiveHour),
                                outlook: fiveHourOutlook)
    }

    /// 7 天那一欄的註腳：絕對重置時間 + 每日均量。
    ///
    /// 倒數（「剩 21h 5m」）對五小時窗口有用，對七天窗口沒有 —— 你想知道的是
    /// 「星期幾會重置」與「這樣燒下去來不來得及」。
    private var sevenDayCaption: String {
        guard let w = store.usage?.sevenDay, let reset = w.resetsAt,
              let u = store.usage else { return " " }
        let avg = UsagePace.dailyAverage(percent: w.percent, resetsAt: reset,
                                         windowLength: UsagePace.sevenDay, now: u.fetchedAt)
        return OutlookCaption.sevenDay(resetText: Self.weekdayTime.string(from: reset),
                                       dailyAverage: avg, outlook: sevenDayOutlook)
    }

    /// 「週六 下午1:59」。
    ///
    /// ⚠️ 不可以直接用 `Locale.current` 或 `Locale.preferredLanguages.first`。
    /// 這台機器的偏好語言是 `["en-TW", "zh-Hant-TW"]` —— 第一個是英文，
    /// 於是在一整排中文裡冒出一句「Sat 2:00 PM」。
    ///
    /// 這個 app 的介面字串全部是繁體中文（沒有在地化資源），所以日期也用中文，
    /// 但**地區**照使用者的，這樣 12/24 小時制、週起始日這些慣例才是對的。
    private static let weekdayTime: DateFormatter = {
        let f = DateFormatter()
        let region = Locale.current.region?.identifier ?? "TW"
        f.locale = Locale(identifier: "zh-Hant-\(region)")
        f.setLocalizedDateFormatFromTemplate("EEE jmm")
        return f
    }()

    /// 一條進度條的顏色：依**它自己**的剩餘量取色，與選單列圖示共用同一份色階。
    ///
    /// 每一欄各自判斷，而不是整排跟著圖示走 —— 圖示取的是「最緊的那個窗口」，
    /// 但面板上三個數字是分開的，5 小時很緊不該把 7 天那條也染紅。
    private func barColour(_ w: UsageWindow?) -> Color {
        guard let w else { return .secondary }
        // ⚠️ `?? .standard` —— 解析寫在注入點，字面量仍然只活在 `QuotaThresholds.standard`。
        return QuotaPalette.color(.forUsed(percent: w.percent,
                                           thresholds: store.quotaThresholds),
                                  onDark: onDark)
    }

    private func cell(_ title: String, _ w: UsageWindow?,
                      caption: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 9.5, weight: .medium)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                // 沒有讀數時顯示 — 而不是 0%。空的量表與「不知道」必須看得出來不同。
                Text(w.map { "\($0.percent)" } ?? "—")
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .monospacedDigit()
                if w != nil {
                    Text("%").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                }
            }
            bar(w?.percent, accent: barColour(w))
            Text(caption ?? resetText(w)).font(.system(size: 9)).foregroundStyle(.tertiary)
                .lineLimit(1).minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .opacity(store.usage?.freshness == .expired ? 0.5 : 1)
    }

    /// 第三欄：分模型的 7 天用量。
    ///
    /// ⚠️ 這一欄與左邊兩欄**不是同一個來源**。分模型只有 `~/.claude.json` 有
    /// （statusLine payload 沒有這個欄位），而那份快取實測可以 16 小時不更新。
    /// 所以它一定要標出自己的年齡 —— 否則使用者會以為它跟旁邊的總量一樣新。
    private var perModelCell: some View {
        let entry = store.scoped?.scoped.max { $0.percent < $1.percent }
        return VStack(alignment: .leading, spacing: 4) {
            Text(entry.map { "7 天 · \($0.modelName.uppercased())" } ?? "7 天 · 分模型")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(entry.map { "\($0.percent)" } ?? "—")
                    .font(.system(size: 22, weight: .medium, design: .rounded)).monospacedDigit()
                if entry != nil {
                    Text("%").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                }
            }
            bar(entry?.percent,
                accent: entry.map { QuotaPalette.color(.forUsed(percent: $0.percent,
                                                                thresholds: store.quotaThresholds),
                                                       onDark: onDark) } ?? .secondary)
            Text(perModelCaption(entry))
                .font(.system(size: 9)).foregroundStyle(.tertiary)
                .lineLimit(1).minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
    }

    /// 分模型那一欄的註腳：有數字就標**它自己的年齡**，沒數字就說對原因。
    ///
    /// 「此方案無此視窗」只有在真的讀到 `~/.claude.json` 而它沒有分模型項目時才成立。
    private func perModelCaption(_ entry: ScopedUsage?) -> String {
        guard entry != nil, let breakdown = store.scoped else {
            return store.scoped == nil ? "讀不到 ~/.claude.json" : "此方案無分模型視窗"
        }
        let age = breakdown.age(now: Date())
        if age < 90 { return "剛更新" }
        if age < 3600 { return "\(Int(age / 60)) 分鐘前" }
        if age < 86400 { return "\(Int(age / 3600)) 小時前" }
        return "\(Int(age / 86400)) 天前"
    }

    private func bar(_ percent: Int?, accent: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary).frame(height: 3)
                if let p = percent {
                    Capsule().fill(accent)
                        .frame(width: geo.size.width * CGFloat(p) / 100, height: 3)
                }
            }
        }
        .frame(height: 3)
    }

    private func resetText(_ w: UsageWindow?) -> String {
        guard let r = w?.resetsAt else { return " " }
        guard let left = ResetTimestamp.remaining(until: r, now: Date()) else { return "已重置" }
        let h = Int(left) / 3600, m = (Int(left) % 3600) / 60
        return h > 0 ? "剩 \(h)h \(m)m" : "剩 \(m)m"
    }

    /// 說出新鮮度，也說出**來源** —— 兩個來源的「舊」代表完全不同的事情。
    ///
    /// ⚠️ 這裡原本有一句：「statusline tee 是事件驅動的：會讓額度變大的活動
    /// 本身就會觸發重新寫入，所以它的『舊』通常代表『你沒在用』。」
    /// **後半段成立，前半段的推論在 2026-09-21 被實測推翻** ——
    /// 渲染是 UI 事件驅動的，不是 API 回應驅動的，所以一次渲染可以完全不帶新數字
    /// （理由見 `UsageSourceSelector.snapshot(from:now:)` 與規矩 31）。
    ///
    /// 字串本身全部搬進 `UsageSourceCaption`（Core）—— 這裡的風險全在文案上，
    /// 而 App 層沒有測試守得住它。
    private var freshnessText: String {
        UsageSourceCaption.text(usage: store.usage, source: store.usageSource,
                                statusLinePayloadCount: store.statusLinePayloadCount)
    }

    // ── 阻塞（釘住，永遠可見）──────────────────────────────────

    @ViewBuilder private var blockedBanner: some View {
        let blocked = store.sessions.filter(\.needsHuman)
        if !blocked.isEmpty {
            VStack(spacing: 6) {
                ForEach(blocked, id: \.session.sessionId) { s in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color.orange).frame(width: 3)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(store.displayName(for: s.session))
                                    .font(.system(size: 12, weight: .semibold))
                                Text(s.project).font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("等你回覆").font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.orange)
                            }
                            Text(s.waitingFor == .permissionPrompt
                                 ? "PERMISSION · 等待你批准一個工具呼叫"
                                 : "INPUT · 它在問你問題")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                            // 說出後果，不只說出存在。
                            if let n = stalledAgents(s), n > 0 {
                                Text("\(n) 個 agent 跟著停住")
                                    .font(.system(size: 10)).foregroundStyle(.orange.opacity(0.9))
                            }
                        }
                    }
                    .padding(9)
                    .background(RoundedRectangle(cornerRadius: 7)
                        .fill(Color.orange.opacity(0.12)))
                    .overlay(RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(Color.orange.opacity(0.35), lineWidth: 0.5))
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
        }
    }

    private func stalledAgents(_ s: LiveSession) -> Int? {
        store.trees[s.session.sessionId]?.runningAgentCount
    }

    // ── session 清單（唯一會捲動的區域）────────────────────────

    // ── 清單高度 ───────────────────────────────────────────────
    //
    // 面板的高度要跟著 session 多寡走：一個 session 就短，三個以上才捲動。
    //
    // ⚠️ 高度是**同步算出來的**，不是用 GeometryReader 量的。
    //    量的那條路（preference + onPreferenceChange）要等下一輪 runloop 才有值，
    //    而 StatusItemController 在展開的那一瞬間就要拿 fittingSize 去設
    //    popover.contentSize —— 第一次展開會拿到還沒算好的高度，面板就縮了一半。
    //    這裡寧可用估的：估錯幾 pt 由 ScrollView 吸收，看不出來。

    /// 一列 session 裡每一行的高度（含與上一行的間距）。對照 `SessionRow` 的版面。
    private enum RowMetrics {
        static let padding: CGFloat = 18        // 上下各 9
        // ⚠️ 引用 SessionRow 自己釘死的那個高度，不要再寫一次 16 ——
        // 兩份字面量只要有一次只改了一邊，整個面板的高度就會算錯，
        // 而這個估算是同步做的（量的要等下一輪 runloop）。
        static let header: CGFloat = SessionRow.headerHeight   // 名稱那一行
        static let contextLine: CGFloat = 15    // ctx 壓力細條（5 間距 + 10）
        static let detailLine: CGFloat = 18     // workflow / agent / 「另有 N 個已完成」
        static let spacing: CGFloat = 8         // 列與列之間
        static let bottomPadding: CGFloat = 10
    }

    /// 不捲動就能看到的列數。使用者明確要求至少三個。
    private static let visibleRows = 3

    private func estimatedHeight(of s: LiveSession) -> CGFloat {
        var h = RowMetrics.padding + RowMetrics.header
        if store.statusLine[s.session.sessionId]?.contextUsedPercent != nil {
            h += RowMetrics.contextLine
        }
        if let tree = store.trees[s.session.sessionId] {
            let live = tree.workflows.filter { $0.runningCount > 0 }.count
            let finished = tree.workflows.count - live
            h += CGFloat(live + tree.agents.count) * RowMetrics.detailLine
            if finished > 0 { h += RowMetrics.detailLine }
        }
        return h
    }

    private var listedSessions: [LiveSession] { store.sessions.filter { !$0.needsHuman } }

    /// 清單要多高：內容的高度，但夾在「一列」與「三列」之間。
    private var listHeight: CGFloat {
        let heights = listedSessions.map(estimatedHeight(of:))
        guard !heights.isEmpty else { return 72 }       // 「目前沒有執行中的 session」那行
        let total = heights.reduce(0, +)
            + RowMetrics.spacing * CGFloat(heights.count - 1)
            + RowMetrics.bottomPadding

        let sorted = heights.sorted(by: >)
        let floor = sorted[0] + RowMetrics.bottomPadding
        let ceiling = sorted.prefix(Self.visibleRows).reduce(0, +)
            + RowMetrics.spacing * CGFloat(min(heights.count, Self.visibleRows) - 1)
            + RowMetrics.bottomPadding
        return min(max(total, floor), ceiling)
    }

    private var sessionList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("工作階段 SESSIONS").sectionLabel()
                Spacer()
                Text("\(store.summary.blocked) 等待 · \(store.summary.working) 執行 · "
                     + "\(store.summary.idle) 閒置")
                    .font(.system(size: 9.5)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 6)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(listedSessions, id: \.session.sessionId) { s in
                        SessionRow(session: s,
                                   title: store.displayName(for: s.session),
                                   tree: store.trees[s.session.sessionId],
                                   context: store.statusLine[s.session.sessionId],
                                   finish: store.finishes[s.session.sessionId],
                                   now: store.lastRefresh,
                                   contextYellow: store.preferences.contextYellow
                                       ?? SessionRow.defaultContextYellow,
                                   contextRed: store.preferences.contextRed
                                       ?? SessionRow.defaultContextRed)
                    }
                    if store.sessions.isEmpty {
                        Text("目前沒有執行中的 Claude Code session")
                            .font(.system(size: 11)).foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity).padding(.vertical, 20)
                    }
                }
                .padding(.horizontal, 12).padding(.bottom, 10)
            }
            // ScrollView 在垂直方向是貪婪的，不夾住的話它會把面板撐到最高。
            // 夾在「一列」與「三列」之間：一個 session 時面板短，三個以上才捲動。
            .frame(height: listHeight)
        }
    }

    // ── 底部 ───────────────────────────────────────────────────

    private var footer: some View {
        HStack(spacing: 12) {
            Button { store.refresh() } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 10.5))
            }
            .buttonStyle(.plain)
            Text("更新於 \(relative(store.lastRefresh))")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
            Spacer()
            Button { openPreferences?() } label: {
                Image(systemName: "gearshape").font(.system(size: 10.5))
            }
            .buttonStyle(.plain)
            .help("偏好設定")
            loginItemControl
            muteControl
            Button { NSApp.terminate(nil) } label: {
                Image(systemName: "power").font(.system(size: 10.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    /// 開機時自動啟動。
    ///
    /// ⚠️ **不是 .app bundle 的時候整個不畫。** 診斷指令（`--render-panel`）
    /// 就是那種情況 —— 一個按了保證沒用的按鈕比沒有按鈕更糟。
    @ViewBuilder private var loginItemControl: some View {
        if loginItem.isVisible {
            Button {
                LoginItem.apply(loginItem.action)
                // ⚠️ **重讀，不要自己翻旗標。** 註冊可能失敗、也可能被系統設定
                // 擋著，而真相在系統那邊，不在我們的布林值裡。
                loginItem = LoginItem.state
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: loginItem == .on ? "power.circle.fill" : "power.circle")
                        .font(.system(size: 10.5))
                    if let caption = loginItem.caption {
                        Text(caption).font(.system(size: 10))
                    }
                }
                .foregroundStyle(loginItem == .on ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(loginItem.help)
        }
    }

    /// 手動靜音。
    ///
    /// ⚠️ **這裡永遠不會有「安靜時段」的排程設定。** macOS Focus 已經做了那件事，
    /// 而第二個排程器正是「明明開了勿擾卻在半夜三點響」的成因。
    /// 而且 Focus 狀態實測讀不到（Assertions.json 受 TCC 保護、沒有公開 API），
    /// 所以這兩個選項是使用者唯一的防線 —— 它們要好按，而且要看得出現在是哪個狀態。
    private var muteControl: some View {
        // ⚠️ 刻意**不用** `Menu`。已證實的理由是它在離屏渲染下畫成一個紅色禁止符號，
        // 於是 `--render-panel` 對這個角落說不出真話；未證實但足以避開的理由是
        // `.transient` 的 popover 很可能在 Menu 開視窗的那一下自己關掉。
        // 完整說明見 `MutePolicy.next`。
        // 循環鍵沒有第二個視窗：關 → 1 小時 → 到明早 → 關，而且現在是哪一段
        // 一直寫在旁邊。順序由 `MutePolicy.next` 決定，那裡有測試。
        Button {
            // ⚠️ `?? MutePolicy.morningHour` —— 解析寫在注入點，看得見。
            // 字面量 8 仍然只活在 `MutePolicy.swift`，這不是第二份定義。
            store.setMute(MutePolicy.next(
                from: store.mutedUntil, now: Date(),
                morningHour: store.preferences.morningHour ?? MutePolicy.morningHour))
        } label: {
            HStack(spacing: 4) {
                Image(systemName: store.isMuted ? "bell.slash.fill" : "bell")
                    .font(.system(size: 10))
                if let until = store.mutedUntil, store.isMuted {
                    Text("靜音至 \(clock(until))")
                        .font(.system(size: 10)).monospacedDigit()
                }
            }
            .foregroundStyle(store.isMuted ? Color.orange : Color.secondary)
        }
        .buttonStyle(.plain)
        .help(store.isMuted ? "點一下換下一段，再點一下解除" : "靜音 1 小時")
    }

    private func clock(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    private func relative(_ d: Date) -> String {
        let s = Int(Date().timeIntervalSince(d))
        return s < 5 ? "剛剛" : s < 60 ? "\(s) 秒前" : "\(s / 60) 分鐘前"
    }
}

private extension Text {
    func sectionLabel() -> some View {
        self.font(.system(size: 9.5, weight: .semibold))
            .tracking(0.7)
            .foregroundStyle(.secondary)
    }
}
