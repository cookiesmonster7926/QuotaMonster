import SwiftUI
import QuotaMonsterCore

/// 一個 session 及其底下的 agent 結構。
///
/// 層級不用縮排表示，而是用**不同的 row 型別** —— 這樣樹再深也不會往右邊爬，
/// 7 隻 agent 的扇出只吃 3 行而不是 7 行。
struct SessionRow: View {
    let session: LiveSession
    /// 這一列要顯示的名字。由 `DataStore.displayName(for:)` 算好傳進來 ——
    /// 它要讀 transcript，不可以在 body 裡做。
    let title: String
    let tree: AgentTree?
    /// 這個 session 最後一次的 statusLine payload。只有裝了 tee 才會有。
    let context: StatusLinePayload?
    /// 這個 session 剛剛講完了一輪。nil 代表沒有。
    let finish: SessionFinish?
    /// ⚠️ 從外面注入，**不在這裡呼叫 `Date()`** —— 同一次繪製裡的所有時間
    /// 要來自同一個時刻，否則鮮度線與「N 分前完成」會各自對著不同的現在。
    let now: Date
    /// context 壓力的兩個門檻。預設值在 `defaultContextYellow` / `defaultContextRed`。
    let contextYellow: Int
    let contextRed: Int

    @Environment(\.colorScheme) private var scheme

    /// header 那一行的高度。⚠️ **釘死它**，因為 `PanelView.RowMetrics.header`
    /// 是**同步估算**的（量的要等下一輪 runloop，第一次展開會縮一半）——
    /// 換成勾之後那一行如果長高，整個面板的高度就會算錯。
    nonisolated static let headerHeight: CGFloat = 16

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            header
            contextRow
            if let tree {
                // 只顯示還在跑的。已完成的 workflow 收合成一行 ——
                // 八個 10/10 的綠色 pip 沒有告訴你任何需要知道的事，
                // 只是把還在跑的那一個推出畫面。
                let live = tree.workflows.filter { $0.runningCount > 0 }
                let tally = WorkflowTally(tree.workflows)

                ForEach(live, id: \.workflowId) { wf in
                    workflowRow(wf)
                }
                ForEach(Array(tree.agents.enumerated()), id: \.offset) { _, a in
                    agentRow(a)
                }
                if !tally.collapsed.isEmpty {
                    HStack(spacing: 6) {
                        Rectangle().fill(.quaternary).frame(width: 1).padding(.leading, 2)
                        // ⚠️ 這一行本來寫「另有 N 個 workflow 已完成」，把失敗的也
                        // 算進去。而 T2 刻意不對失敗的批次出聲（那是對的），
                        // 所以這一行是「有東西壞了」唯一的落腳處。
                        // 分類在 `WorkflowTally`，那邊有測試。
                        Text("另有").font(.system(size: 9.5)).foregroundStyle(.tertiary)
                        ForEach(Array(tally.collapsed.enumerated()), id: \.offset) { i, part in
                            if i > 0 {
                                Text("·").font(.system(size: 9.5)).foregroundStyle(.quaternary)
                            }
                            Text(part.text)
                                .font(.system(size: 9.5))
                                .foregroundStyle(tallyColour(part.outcome))
                        }
                        Spacer()
                    }
                }
            }
        }
        .padding(9)
        .background(RoundedRectangle(cornerRadius: 7).fill(.quaternary.opacity(0.35)))
    }

    private var header: some View {
        HStack(spacing: 7) {
            // ⚠️ **固定 10pt 槽。** 圓點 6pt、勾 9.5pt —— 不給固定寬度的話，
            // 一輪講完的那一刻整列的名字會往右跳一下。
            ZStack {
                if finish != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(SignalPalette.color(glow, onDark: scheme == .dark))
                } else {
                    Circle()
                        .fill(session.isWorking ? Color.accentColor
                                                : Color.secondary.opacity(0.5))
                        .frame(width: 6, height: 6)
                }
            }
            .frame(width: 10, height: 10)
            // ⚠️ 不可以直接用 `session.session.name` —— 那在 nameSource 是 "derived"
            // 時是 Claude Code 從 cwd 湊的佔位名（`rl-1b`），使用者從來沒有看過它。
            // 由 `DataStore.displayName(for:)` 解析（判準在 Core 的 `SessionTitle`）。
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1).truncationMode(.tail).layoutPriority(2)
            Text(session.project)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle).layoutPriority(0)
            Spacer(minLength: 4)
            // 狀態與時間永遠不被擠掉 —— 它們比完整路徑重要。
            HStack(spacing: 6) {
                if let finish {
                    Text(FinishCaption.label(finishedAt: finish.finishedAt, now: now))
                        .font(.system(size: 10))
                        .foregroundStyle(SignalPalette.color(glow, onDark: scheme == .dark))
                    // ⚠️ 算不出跑多久就**整格不畫**。「跑了 0m 00s」看起來像一個
                    // 量到的數字，而〔實測〕約六分之一的完成根本算不出來。
                    if let ran = FinishCaption.ranFor(finish.ranFor) {
                        Text(ran)
                            .font(.system(size: 10, design: .monospaced)).monospacedDigit()
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    Text(session.isWorking ? "BUSY" : "IDLE")
                        .font(.system(size: 8.5, weight: .semibold)).tracking(0.5)
                        .foregroundStyle(session.isWorking
                                         ? AnyShapeStyle(Color.accentColor)
                                         : AnyShapeStyle(.tertiary))
                    Text(elapsed)
                        .font(.system(size: 10, design: .monospaced)).monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
            }
            .fixedSize()
            .layoutPriority(3)
        }
        // ⚠️ 高度釘死 —— 見 `headerHeight`。
        .frame(height: Self.headerHeight)
        .overlay(alignment: .topLeading) { freshnessLine }
    }

    /// 這個 session 現在該用哪一格丁香紫。
    private var glow: FinishGlow {
        FinishGlow.at(finishedAt: finish?.finishedAt, now: now)
    }

    /// 坐在卡片上緣、10 分鐘內排空的鮮度線。**高度成本 0pt**（它是 overlay）。
    @ViewBuilder private var freshnessLine: some View {
        if let finish {
            GeometryReader { geo in
                Rectangle()
                    .fill(SignalPalette.color(glow, onDark: scheme == .dark))
                    .frame(width: geo.size.width
                           * CGFloat(FinishCaption.drainFraction(finishedAt: finish.finishedAt,
                                                                 now: now)),
                           height: 1.5)
            }
            .frame(height: 1.5)
            .offset(y: -6)
            .allowsHitTesting(false)
        }
    }

    /// context 壓力。只有 statusline tee 拿得到這個數字 —— 磁碟上沒有別的地方記錄它。
    ///
    /// 沒有讀數時整行不顯示，而不是顯示 0% 或一條空的長條。
    /// 一條 0% 的長條看起來像「還很空」，但實際意思是「不知道」。
    @ViewBuilder private var contextRow: some View {
        if let used = context?.contextUsedPercent {
            HStack(spacing: 6) {
                Text("ctx")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary).frame(height: 3)
                        Capsule().fill(contextColour(used))
                            .frame(width: geo.size.width * CGFloat(used) / 100, height: 3)
                    }
                    .frame(height: 3)
                    .frame(maxHeight: .infinity, alignment: .center)
                }
                .frame(height: 9)
                Text("\(used)%")
                    .font(.system(size: 9.5, design: .monospaced)).monospacedDigit()
                    // ⚠️ 這裡本來寫死了第二份 `70` —— 規矩 2（門檻只能定義在一處）
                    // 今天就被違反著，只是沒有人發現：改了 contextColour 的門檻
                    // 而忘了這一行，數字的顏色與它自己的粗細就會在 70 那一格
                    // 各說各話。
                    .foregroundStyle(used >= contextYellow
                                     ? AnyShapeStyle(contextColour(used))
                                     : AnyShapeStyle(.secondary))
                if let window = context?.contextWindowSize {
                    Text(window >= 1_000_000 ? "1M" : "\(window / 1000)k")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    /// 收合那一行的顏色。
    ///
    /// **失敗用紅** —— 面板裡紅色已經是「壞消息」（ctx ≥ 90% 就是紅的），
    /// 借同一個語彙不會多開一套。
    /// ⚠️ **不可以用琥珀／黃** —— 那是「要你輸入」專屬的，
    /// 拿去表示別的東西會把整個 app 裡唯一有時限的訊號稀釋掉。
    /// 「狀態不明」用 secondary 而不是紅：它不是壞消息，它是**沒有消息**。
    private func tallyColour(_ o: WorkflowTally.Outcome) -> AnyShapeStyle {
        switch o {
        case .failed:  return AnyShapeStyle(.red)
        case .unknown: return AnyShapeStyle(.secondary)
        default:       return AnyShapeStyle(.tertiary)
        }
    }

    /// context 壓力的兩個門檻。
    ///
    /// **權威不在這個 repo 裡，在使用者自己的狀態列腳本裡** —— 這兩個數字抄的是
    /// 那份腳本（70% 黃、90% 紅），兩邊看起來才是同一個系統，而不是兩套
    /// 各說各話的顏色。
    ///
    /// ⚠️ 規矩 24（黃／琥珀只代表「要你輸入」）**唯一授權的例外就是這裡**，
    /// 而授權的理由正是「它抄的是使用者自己的色階」。一旦這兩個數獨立於那份
    /// 腳本漂走，那個例外就失去理由，面板上會出現一個沒有依據的黃色。
    /// **預設值**，唯一的字面量定義處。使用者可以在偏好裡覆寫
    /// （`Preferences.contextYellow` / `.contextRed`）—— 覆寫不是第二份定義，
    /// 解析寫在注入點（`PanelView`）看得見的 `?? SessionRow.defaultContextYellow`。
    static let defaultContextYellow = 70
    static let defaultContextRed = 90

    private func contextColour(_ percent: Int) -> Color {
        percent >= contextRed ? .red
            : percent >= contextYellow ? .yellow : .green
    }

    /// 扇出先給「形狀」再給名字：一排 pip 讓你在讀到任何文字之前就知道進度。
    private func workflowRow(_ wf: WorkflowGroup) -> some View {
        HStack(spacing: 6) {
            Rectangle().fill(.quaternary).frame(width: 1).padding(.leading, 2)
            Text(wf.latestPhase ?? "workflow")
                .font(.system(size: 10.5, weight: .medium))
            Text(wf.workflowId)
                .font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 4)
            HStack(spacing: 2) {
                ForEach(0..<min(wf.total, 10), id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(i < wf.finishedCount ? Color.green.opacity(0.75)
                              : Color.accentColor.opacity(0.75))
                        .frame(width: 5, height: 7)
                }
            }
            Text("\(wf.finishedCount)/\(wf.total)")
                .font(.system(size: 9.5, design: .monospaced)).monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private func agentRow(_ a: AgentNode) -> some View {
        HStack(spacing: 6) {
            Rectangle().fill(.quaternary).frame(width: 1).padding(.leading, 2)
            Circle().fill(colour(a.runState)).frame(width: 4, height: 4)
            Text(a.meta.description)
                .font(.system(size: 10.5)).lineLimit(1)
            Spacer(minLength: 4)
            Text(a.meta.agentType)
                .font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }

    private func colour(_ s: AgentRunState) -> Color {
        switch s {
        case .running: return .accentColor
        // ⚠️ 降調是**載重的**：這顆點是推定的，不可以畫得跟 journal 讀到的一樣篤定。
        // 判準與誤差見 `AgentActivity`（實測 0.45% 的時刻會誤判）。
        case .likelyRunning: return .accentColor.opacity(0.45)
        case .finished: return .green.opacity(0.7)
        case .unknown: return .secondary.opacity(0.45)   // 誠實標示，不假裝知道
        }
    }

    private var elapsed: String {
        let s = Int(now.timeIntervalSince(session.session.startedAt))
        return s < 60 ? "\(s)s" : s < 3600 ? "\(s / 60)m" : "\(s / 3600)h"
    }
}
