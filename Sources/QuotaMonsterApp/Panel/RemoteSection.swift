import SwiftUI
import QuotaMonsterCore

/// 面板的「遠端 REMOTE」那一區：herdr 連著的其他機器上的 Claude session。
///
/// 版面是使用者選的「一台一行」（mockup 三選一）：每台機器一張卡，計數一行，
/// **只有等你回覆的展開成一列** —— 遠端不跳通知、不進選單列的計數，所以面板上最值得說的就是「那台有人在等你」。
/// 被拒絕的兩個：每個 session 一列（一台 6 個就多 6 列，面板本來就是高度出事）、
/// 混進本機清單（要捲到底才看得到；連不上時每列重複機器名）。
///
/// 畫什麼、寫什麼字全部由 `RemoteTracker.view`（Core）決定；這裡只照著畫。
/// 遠端的列**不畫跑了多久**：herdr 的原生欄位沒有時間戳，畫了就是編的。
///
/// ⚠️ 這一區不在 session 清單的 ScrollView 裡：它是固定高度、不壓縮的。面板碰到螢幕上限時
/// 由 session 清單吸收（`CappedHeight`），這一區照常畫。
struct RemoteSection: View {
    let view: RemoteView
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        switch view {
        case .hidden:
            EmptyView()
        case .notice(let text):
            Divider().opacity(0.5)
            VStack(alignment: .leading, spacing: 6) {
                title
                Text(text).font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
        case .machines(let cards, let listNote):
            Divider().opacity(0.5)
            VStack(alignment: .leading, spacing: 6) {
                title
                if let listNote {
                    Text(listNote).font(.system(size: 10)).foregroundStyle(.orange)
                }
                ForEach(cards, id: \.id) { card($0) }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
        }
    }

    private var title: some View {
        HStack {
            Text("遠端 REMOTE")
                .font(.system(size: 9.5, weight: .semibold)).tracking(0.7)
                .foregroundStyle(.secondary)
            Spacer()
            // 不在 herdr 分頁裡的 session 這裡看不到〔實測：一台 Windows 的 6 個 Claude 只看到 4 個〕
            Text("經 herdr · 只看得到 herdr 分頁裡的")
                .font(.system(size: 9.5)).foregroundStyle(.tertiary)
        }
    }

    private func card(_ c: RemoteCard) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                Text(c.label).font(.system(size: 11, weight: .semibold))
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 6)
                if c.warning {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9)).foregroundStyle(.orange)
                }
                Text(c.caption)
                    .font(.system(size: 10))
                    .foregroundStyle(c.warning ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.tertiary))
                    .lineLimit(1).fixedSize()
            }
            if let counts = c.counts {
                if let note = c.note {
                    Text(note).font(.system(size: 10.5)).foregroundStyle(.tertiary)
                } else {
                    HStack(spacing: 10) {
                        ForEach(counts, id: \.text) { n in
                            HStack(spacing: 4) {
                                Circle().fill(colour(n.status)).frame(width: 6, height: 6)
                                Text(n.text).font(.system(size: 10.5)).monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .opacity(c.countsDimmed ? 0.45 : 1)
                }
            }
            ForEach(Array(c.waiting.enumerated()), id: \.offset) { _, s in
                waitingRow(s)
            }
        }
        .padding(9)
        .background(RoundedRectangle(cornerRadius: 7).fill(.quaternary.opacity(0.35)))
    }

    /// 等你回覆的那一列。與本機那張阻塞卡同一套顏色（橘），但小一號 —— 它不是釘住的卡。
    /// herdr 說不出是在等權限還是在問問題，所以只寫「等你回覆」。
    private func waitingRow(_ s: RemoteSession) -> some View {
        let name = RemoteWords.waitingLabel(s)
        return HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5).fill(Color.orange).frame(width: 3)
            Text(name.main)
                .font(.system(size: 11.5, weight: .medium))
                .lineLimit(1).truncationMode(.tail).layoutPriority(1)
            if let p = name.sub {
                Text(p).font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 4)
            Text("等你回覆").font(.system(size: 10, weight: .medium))
                .foregroundStyle(.orange).fixedSize()
        }
        .frame(height: 16)
        .padding(.horizontal, 7).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.12)))
    }

    /// 與本機 session 列同一套語彙：執行＝accent、等你＝橘、完成＝丁香紫、其餘灰。
    private func colour(_ s: RemoteStatus) -> AnyShapeStyle {
        switch s {
        case .working: return AnyShapeStyle(Color.accentColor)
        case .blocked: return AnyShapeStyle(Color.orange)
        case .done:    return AnyShapeStyle(SignalPalette.color(.fresh, onDark: scheme == .dark))
        case .idle, .unknown: return AnyShapeStyle(Color.secondary.opacity(0.5))
        }
    }
}
