import SwiftUI
import QuotaMonsterCore

/// 7 天窗口裡每一天用掉多少。
///
/// ### ⚠️ 一天切在 `resetsAt` 的那個鐘點，不是午夜
/// 使用者 2026-09-22 拍板。換來的性質是**七根相加恰好等於面板的 7 天已用** ——
/// 圖表自己驗自己。代價是「今天」指的是昨天那個鐘點到今天那個鐘點。
/// 標籤用**起始日**的日期，因為那一天是從那時開始的。
///
/// ### ⚠️ 四種狀態要畫得出差別，尤其是「不知道」
/// `unknown` **不可以畫成 0%**。那天可能只是 app 沒開，而把「我沒在看」
/// 畫成「你沒有用」正是這張圖最容易犯、也最難被發現的謊。
/// 它畫成一個虛線的空框，明顯地不是一根長條。
///
/// 判準全部在 `DailyUsage`（Core，16 則測試）。這裡只負責畫。
struct DailyBarChart: View {

    let bars: [DailyUsageBar]

    private static let barArea: CGFloat = 34
    /// 只用在「還沒到」與「不知道」那兩種沒有高度的形狀上 ——
    /// 有數字的那幾根靠 `.frame(maxWidth: .infinity)` 平分寬度。
    private static let barWidth: CGFloat = 26

    /// 縱軸的上限。
    ///
    /// ⚠️ 至少要到均速線，否則「今天燒得比均速慢」那種日子會讓線跑到框外，
    /// 而那條線正是這張圖唯一的參考。
    private var scale: Double {
        max(Double(bars.compactMap(\.percent).max() ?? 0), DailyUsage.evenPacePercent * 1.15)
    }

    private var todayIndex: Int? {
        bars.last { $0.percent != nil || $0.state == .unknown }?.index
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("每日用量 · 這個 7 天視窗")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary).kerning(0.6)
                Spacer()
                Text("虛線＝均速 \(Int(DailyUsage.evenPacePercent.rounded()))%／天")
                    .font(.system(size: 9)).foregroundStyle(.tertiary)
            }
            // ⚠️ 兩列必須用**完全一樣**的分欄方式，否則長條與日期會對不齊。
            // 第一版把長條放進 ZStack —— ZStack 會把比較窄的那一層置中，
            // 而標籤那一列靠左，結果整排錯位（`--render-panel` 一眼看到）。
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(bars, id: \.index) { bar in
                    column(bar).frame(maxWidth: .infinity)
                }
            }
            // ⚠️ alignment 不可省：沒有它，HStack 只有內容那麼高，
            // 然後被垂直**置中**在 34pt 的框裡 —— 長條會浮在半空中。
            .frame(height: Self.barArea, alignment: .bottom)
            // 均速線畫在長條**後面**：被蓋住就代表那天超支，那是刻意的。
            .background(paceLine)
            HStack(spacing: 5) {
                ForEach(bars, id: \.index) { bar in
                    Text(Self.dayLabel(bar.start))
                        .font(.system(size: 8.5, design: .monospaced))
                        .foregroundStyle(bar.index == todayIndex ? .primary : .tertiary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var paceLine: some View {
        GeometryReader { geo in
            let y = geo.size.height * (1 - DailyUsage.evenPacePercent / scale)
            Path { p in
                p.move(to: CGPoint(x: 0, y: y))
                p.addLine(to: CGPoint(x: geo.size.width, y: y))
            }
            .stroke(style: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
            .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func column(_ bar: DailyUsageBar) -> some View {
        let w = Self.barWidth
        switch bar.state {
        case .notYet:
            // 還沒到 ≠ 0%。畫一條幾乎看不見的底線，佔住位置就好。
            RoundedRectangle(cornerRadius: 1.5)
                .fill(.quaternary).frame(width: w, height: 1.5)
        case .unknown:
            // ⚠️ 虛線空框，明顯地不是一根長條 —— 「我沒在看」不可以看起來像「你沒有用」。
            RoundedRectangle(cornerRadius: 2)
                .stroke(style: StrokeStyle(lineWidth: 0.8, dash: [2, 2]))
                .foregroundStyle(.tertiary)
                .frame(width: w, height: Self.barArea * 0.55)
                .help("那段時間 QuotaMonster 沒有在跑，所以說不出這一天用了多少")
        case .measured(let p):
            column(percent: p, opacity: 1, isToday: bar.index == todayIndex)
                .help(Self.range(bar) + "　用掉 \(p)%")
        case .unverified(let p):
            // 有數字但別完全相信：跨日界那一小段沒被看著，歸屬可能落在隔壁那天。
            column(percent: p, opacity: 0.4, isToday: bar.index == todayIndex)
                .help(Self.range(bar) + "　用掉 \(p)% —— ⚠️ 日界附近沒有紀錄，"
                      + "這個數字可能有一部分屬於隔壁那一天")
        }
    }

    private func column(percent: Int, opacity: Double, isToday: Bool) -> some View {
        let h = max(1.5, Self.barArea * min(1, Double(percent) / scale))
        return RoundedRectangle(cornerRadius: 2)
            .fill(Color.accentColor.opacity(opacity))
            .frame(maxWidth: .infinity, minHeight: h, maxHeight: h)
            .overlay(alignment: .top) {
                if isToday {
                    // 今天那一根還在長 —— 頂端留一個記號，不要看起來像已經定案。
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.accentColor)
                        .frame(maxWidth: .infinity, maxHeight: 1.5)
                        .offset(y: -3)
                }
            }
    }

    /// ⚠️ 用**起始日**標，因為這一天是從那個鐘點開始的。
    static func dayLabel(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f.string(from: d)
    }

    static func range(_ bar: DailyUsageBar) -> String {
        let f = DateFormatter()
        f.dateFormat = "M/d HH:mm"
        return f.string(from: bar.start) + " → " + f.string(from: bar.end)
    }
}
