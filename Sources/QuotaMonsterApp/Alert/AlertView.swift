import AppKit
import SwiftUI
import QuotaMonsterCore

/// 浮窗要顯示的東西。純資料 —— 由 presenter 組好再交給 view。
struct AlertContent: Equatable {
    /// 等最久的那一個。與 `WaitingAlert` 同理：拆開存，空的內容就不存在。
    let primary: WaitingSession
    let others: [WaitingSession]
    let coalesced: Bool
    /// 那個 session 真正問出口的句子。讀不到時是 nil，退回分類文字。
    let context: WaitingContext?
    let now: Date

    var sessions: [WaitingSession] { [primary] + others }

    init(primary: WaitingSession, others: [WaitingSession] = [], coalesced: Bool,
         context: WaitingContext?, now: Date) {
        self.primary = primary
        self.others = others
        self.coalesced = coalesced
        self.context = context
        self.now = now
    }

    init(_ alert: WaitingAlert, context: WaitingContext?, now: Date) {
        self.init(primary: alert.primary, others: alert.others,
                  coalesced: alert.coalesced, context: context, now: now)
    }
}

/// T1 浮窗 —— **Question 方向**（使用者 2026-09-18 選定，四份 mockup 見 `alert-mockups/`）。
///
/// 賭注只有一句話：**最大的那一行是那個 session 真正問出口的句子**，
/// 不是 app 的名字，也不是「usage 正在等待輸入」這種轉述。
/// 最快的一次閱讀，是使用者根本不需要先解碼一則通知就已經知道對方要什麼 ——
/// 而且那一行同時決定了「要不要現在切過去」，所以它省掉的往往是一次切換，
/// 不只是一次閱讀。
///
/// 幾何與顏色都從既有的東西來，不另立一套：
///   - 左上角那顆標記就是選單列上那一顆（`GlyphRenderer` 畫的同一張圖）
///   - 琥珀是 `GlyphRenderer.alert`，**這個 app 裡唯一用琥珀的地方就是這裡與圖示**
struct AlertView: View {

    let content: AlertContent
    let onJump: (WaitingSession) -> Void
    let onDismiss: () -> Void

    static let width: CGFloat = 320
    /// 琥珀。與選單列圖示同一個色值 —— 兩個地方講的是同一件事。
    static var amber: Color { Color(nsColor: GlyphRenderer.alert) }

    var body: some View {
        HStack(spacing: 0) {
            // 左側琥珀軌：整扇窗唯一的大色塊，餘光靠它抓到。
            Rectangle().fill(Self.amber).frame(width: 3)

            VStack(alignment: .leading, spacing: 0) {
                header
                hero
                pathRow
                // ⚠️ 條件是 **others 不是空的**，不是 coalesced。
                // 兩個在等時引擎照設計不合併（coalesced == false），但窗口上
                // 只有一扇窗 —— 用 coalesced 當條件的話，第二個 session
                // 在整扇窗上一個字都沒有，連跳轉目標都沒有。
                if !content.others.isEmpty { othersRow }
                actions
            }
            .padding(.leading, 11).padding(.trailing, 12)
            .padding(.top, 8).padding(.bottom, 9)
        }
        .frame(width: Self.width)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Self.amber.opacity(0.32), lineWidth: 0.5)
        }
    }

    // ── 第一列：標記 · 幾個在等 · 等了多久 ──────────────────────

    private var header: some View {
        HStack(spacing: 7) {
            glyph
            if !content.others.isEmpty {
                Text("\(content.sessions.count) 個在等你"
                     + (content.coalesced ? " · 已合併" : ""))
                    .font(.system(size: 9.5, weight: .semibold)).tracking(0.7)
                    .foregroundStyle(.tertiary)
            } else if let name = content.primary.name {
                Text(name)
                    .font(.system(size: 9.5, weight: .semibold)).tracking(0.7)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 6)
            HStack(spacing: 3) {
                Text(content.others.isEmpty ? "等了" : "最久")
                    .font(.system(size: 9.5)).foregroundStyle(.tertiary)
                Text(Self.elapsed(from: content.primary.since, to: content.now))
                    .font(.system(size: 12, design: .monospaced)).monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 16)
    }

    private var glyph: some View {
        Image(nsImage: GlyphRenderer.image(
            for: GlyphState(fiveHourRemaining: nil, sevenDayRemaining: nil,
                            runningAgents: 0, blockedSessions: content.sessions.count,
                            exhausted: false, freshness: .live),
            ink: .labelColor))
            .frame(width: 22, height: 22)
    }

    // ── 英雄行：唯一的主角 ──────────────────────────────────────

    private var hero: some View {
        // ⚠️ **永遠只有一行。** 兩行的英雄行不是英雄行，是段落 ——
        // 而段落要花的時間正好是這個方向想省掉的那一段。
        Text(heroText)
            .font(.system(size: 19, weight: .semibold))
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundStyle(.primary)
            .padding(.top, 4)
            .frame(height: 26, alignment: .leading)
    }

    /// 讀得到問題就用問題；讀不到就退回分類文字 —— **不是留白**。
    /// 留白會讓使用者以為 app 壞了，而那比少一行資訊糟得多。
    private var heroIsFallback: Bool {
        (content.context?.headline ?? "").isEmpty
    }

    private var heroText: String {
        heroIsFallback ? Self.waitingLabel(content.primary.waitingFor)
                       : content.context!.headline
    }

    // ── 路徑 + 分類 ────────────────────────────────────────────

    private var pathRow: some View {
        HStack(spacing: 7) {
            // 前綴壓暗、專案名照常：路徑存在是為了消歧義（同名專案在兩個地方），
            // 而要讀的永遠只有最後一段。
            (Text(Self.parentPath(content.primary.cwd)).foregroundStyle(.tertiary)
                + Text(content.primary.project).foregroundStyle(.secondary))
                .font(.system(size: 10.5, design: .monospaced))
                .lineLimit(1).truncationMode(.head)
            Spacer(minLength: 6)
            // 英雄行已經是分類文字時就不要再掛一個一模一樣的標籤 ——
            // 同一句話說兩次，第二次只是雜訊。
            if !heroIsFallback {
                Text(Self.waitingLabel(content.primary.waitingFor))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Self.amber)
                    .padding(.horizontal, 6).padding(.vertical, 1.5)
                    .background {
                        RoundedRectangle(cornerRadius: 4).fill(Self.amber.opacity(0.16))
                    }
            }
        }
        .padding(.top, 4)
        .frame(height: 17)
    }

    /// cwd 去掉最後一段，家目錄縮成 `~`。
    static func parentPath(_ cwd: String) -> String {
        let parent = (cwd as NSString).deletingLastPathComponent
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let shortened = parent.hasPrefix(home)
            ? "~" + parent.dropFirst(home.count) : parent
        return shortened.hasSuffix("/") ? shortened : shortened + "/"
    }

    // ── 合併時的其餘幾個 ────────────────────────────────────────

    private var othersRow: some View {
        // 合併不該把使用者手上唯一能立刻做的事收走：摘要仍然帶著一個具體的問題，
        // 其餘的只留名字與秒數，而每個名字自己也是跳轉目標。
        HStack(spacing: 5) {
            Text("另外 \(content.others.count) 個")
                .font(.system(size: 10.5)).foregroundStyle(.tertiary)
            ForEach(content.others.prefix(3), id: \.sessionId) { s in
                Button { onJump(s) } label: {
                    HStack(spacing: 2) {
                        Text(s.project).font(.system(size: 10.5, design: .monospaced))
                        Text(Self.elapsed(from: s.since, to: content.now))
                            .font(.system(size: 9.5)).foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 4)
        .frame(height: 15)
    }

    // ── 動作 ───────────────────────────────────────────────────

    private var actions: some View {
        HStack(spacing: 10) {
            Button { onJump(content.primary) } label: {
                HStack(spacing: 4) {
                    Text(content.others.isEmpty
                         ? "跳過去" : "跳過去 · \(content.primary.project)")
                        .font(.system(size: 12.5, weight: .semibold))
                    Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(Color.black)
                .padding(.horizontal, 11).padding(.vertical, 5)
                .background { RoundedRectangle(cornerRadius: 6).fill(Self.amber) }
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)

            Spacer(minLength: 6)

            Button(content.others.isEmpty ? "稍後" : "全部稍後") { onDismiss() }
                .buttonStyle(.plain)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.tertiary)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.top, 8)
    }

    // ── 文字 ───────────────────────────────────────────────────

    static func waitingLabel(_ w: WaitingFor?) -> String {
        switch w {
        case .inputNeeded: return "在問你問題"
        case .permissionPrompt: return "等你批准工具"
        case nil: return "等你回覆"
        }
    }

    static func elapsed(from: Date, to: Date) -> String {
        let s = max(0, Int(to.timeIntervalSince(from)))
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m \(String(format: "%02d", s % 60))s" }
        return "\(s / 3600)h \(String(format: "%02d", (s % 3600) / 60))m"
    }
}
