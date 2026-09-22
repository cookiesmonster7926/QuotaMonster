import SwiftUI
import QuotaMonsterCore

/// 從 7 天窗口起點爬到現在的累計用量。
///
/// ### ⚠️ 這個視圖**沒有歸屬問題**
/// 長條圖要回答「**哪一天**燒的」，所以日界附近看不到就會出錯
/// （帳號是共用的，別人／別的裝置也會燒 —— 見 `WatchLog.Mark.sawLiveReading`）。
/// 這張圖只回答「**到這一刻為止燒了多少**」，那個問題不需要分天。
///
/// 唯一的損失是**空窗那一段的形狀**：兩個觀測點之間畫的是直線，而真實可能是階梯。
/// 總量與每一個端點都是對的。
///
/// ### ⚠️ y 軸固定 0–100%，不隨資料縮放
/// 那條對角線是「**剛好在重置時用完**」—— 曲線在它下面代表來得及，
/// 在上面代表這樣燒會提早觸頂。y 軸一旦隨資料縮放，那條線就失去意義，
/// 而它正是這張圖唯一能回答「會不會用完」的東西。
struct CumulativeChart: View {

    let points: [DailyUsage.CumulativePoint]
    let windowStart: Date
    let resetsAt: Date

    private static let area: CGFloat = 46

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("累計用量 · 這個 7 天視窗")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary).kerning(0.6)
                Spacer()
                // 二選一，判準在 Core（`DailyUsage.cumulativeLegend`）。
                Text(DailyUsage.cumulativeLegend(points))
                    .font(.system(size: 9)).foregroundStyle(.tertiary)
            }
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    dayGrid(geo.size)
                    paceDiagonal(geo.size)
                    curve(geo.size)
                }
            }
            .frame(height: Self.area)
            HStack(spacing: 0) {
                ForEach(0..<DailyUsage.days, id: \.self) { i in
                    Text(Self.dayLabel(windowStart.addingTimeInterval(Double(i) * 86400)))
                        .font(.system(size: 8.5, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func x(_ t: Date, _ size: CGSize) -> CGFloat {
        let span = resetsAt.timeIntervalSince(windowStart)
        guard span > 0 else { return 0 }
        return size.width * CGFloat(min(max(t.timeIntervalSince(windowStart) / span, 0), 1))
    }
    /// ⚠️ 100% 夾住 —— 超過 100 的讀數（實測 spend_limit 可以超過）不可以畫到框外。
    private func y(_ percent: Int, _ size: CGSize) -> CGFloat {
        size.height * (1 - CGFloat(min(max(percent, 0), 100)) / 100)
    }

    /// 七天的分隔線，讓「現在走到第幾天」看得出來。
    private func dayGrid(_ size: CGSize) -> some View {
        Path { p in
            for i in 1..<DailyUsage.days {
                let gx = size.width * CGFloat(i) / CGFloat(DailyUsage.days)
                p.move(to: CGPoint(x: gx, y: 0))
                p.addLine(to: CGPoint(x: gx, y: size.height))
            }
        }
        .stroke(lineWidth: 0.5)
        .foregroundStyle(.quaternary)
    }

    private func paceDiagonal(_ size: CGSize) -> some View {
        Path { p in
            p.move(to: CGPoint(x: 0, y: size.height))
            p.addLine(to: CGPoint(x: size.width, y: 0))
        }
        .stroke(style: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
        .foregroundStyle(.tertiary)
    }

    @ViewBuilder
    private func curve(_ size: CGSize) -> some View {
        if points.count >= 2 {
            let pts = points.map { CGPoint(x: x($0.at, size), y: y($0.percent, size)) }
            ZStack(alignment: .topLeading) {
                // 面積：讓「已經走掉的部分」一眼看得出來
                Path { p in
                    p.move(to: CGPoint(x: pts[0].x, y: size.height))
                    for q in pts { p.addLine(to: q) }
                    p.addLine(to: CGPoint(x: pts.last!.x, y: size.height))
                    p.closeSubpath()
                }
                .fill(Color.accentColor.opacity(0.14))
                // ⚠️ 線分成兩條畫：**可信的**實線、**自相矛盾的**虛線。
                // 一段的兩端只要有一端是矛盾的，那一段就不可信 ——
                // 它的斜率是由那個可疑的讀數決定的。
                // 不夾成遞增：那會把壞資料悄悄改成好資料，而且從此看不出來。
                Path { p in segments(pts, suspect: false, into: &p) }
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.4,
                                                                  lineCap: .round, lineJoin: .round))
                Path { p in segments(pts, suspect: true, into: &p) }
                    .stroke(Color.accentColor.opacity(0.28),
                            style: StrokeStyle(lineWidth: 1.4, lineCap: .round,
                                               lineJoin: .round, dash: [2.5, 2.5]))
                // 現在那一點
                Circle().fill(Color.accentColor).frame(width: 4, height: 4)
                    .offset(x: pts.last!.x - 2, y: pts.last!.y - 2)
            }
        }
    }

    /// 把折線拆成「可信」與「可疑」兩組線段，各自畫成一條 Path。
    private func segments(_ pts: [CGPoint], suspect: Bool, into p: inout Path) {
        for i in 1..<pts.count {
            let bad = points[i].contradictsEarlier || points[i - 1].contradictsEarlier
            guard bad == suspect else { continue }
            p.move(to: pts[i - 1])
            p.addLine(to: pts[i])
        }
    }

    static func dayLabel(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "d"
        return f.string(from: d)
    }
}
