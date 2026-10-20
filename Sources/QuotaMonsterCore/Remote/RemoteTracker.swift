import Foundation

/// 面板「遠端 REMOTE」那一區要畫什麼。
public enum RemoteView: Equatable, Sendable {
    /// 整區不畫：還沒讀過機器清單、或沒裝 herdr。
    case hidden
    /// 一行說明（herdr 沒在跑、沒有連任何機器、機器清單讀不到）。
    case notice(String)
    /// 每台機器一張卡，照機器清單的順序。
    case machines([RemoteCard])
}

/// 一台機器的卡片（使用者 2026-10 選的版面：一台一行計數、只有等你回覆的展開）。
public struct RemoteCard: Equatable, Sendable {
    public let id: String
    public let label: String
    /// 機器名右邊那段：「6 個 · 3 秒前看到」「連不上 · 4 分前最後看到」「讀取中」「還沒讀到 · 逾時」。
    public let caption: String
    /// caption 要不要用警示的樣子（⚠ 與橘色）。
    public let warning: Bool
    /// 計數那一行。nil ＝ 不畫（從沒讀到、或連不上太久 —— 那份計數已經不是現在）。
    public let counts: [RemoteCount]?
    /// 計數是上一次讀到的（現在連不上）—— 要調暗。
    public let countsDimmed: Bool
    /// 等你回覆的那幾個，各自展開成一列。**只有這一輪讀成功時才有**：連不上時那是幾分鐘前的事。
    public let waiting: [RemoteSession]
    /// 讀到了、但一個 Claude session 都沒有時的那一句。
    public let note: String?
}

public struct RemoteCount: Equatable, Sendable {
    public let status: RemoteStatus
    public let n: Int
    /// 「1 等你」「3 閒置」。
    public let text: String
}

/// 遠端機器的狀態與「什麼時候讀」。純的：「現在」從外面傳進來，I/O 在 App 層。
///
/// ### 兩層「不存在」（規矩 1、52）
/// - 讀**成功**、某一列不見了 → 那個 session 結束了（正面證據），計數照新的算
/// - 讀**失敗** → 不是「那台沒有 session」：保留上一次讀到的、標「連不上 · N 前最後看到」，
///   太久（`offlineCut`）就只剩那一行。不可以悄悄少畫一台。
///
/// ### 時間
/// 只用**這台 Mac 的鐘**（讀成功的那一刻）。herdr 的原生欄位沒有時間戳，
/// 也就沒有兩台機器時鐘不一致的問題。
public struct RemoteTracker: Sendable {

    /// 剛加進來的機器，這麼久還沒讀到就不再說「讀取中」。遠端一次最多 5 秒左右〔實測〕。
    public static let loadingGrace: TimeInterval = 15
    /// 連不上超過這麼久，計數就不畫了（那份已經太舊）。
    public static let offlineCut: TimeInterval = 30 * 60
    /// 連續失敗時的退避上限。
    public static let maxBackoff: TimeInterval = 60

    struct Machine: Sendable {
        var info: RemoteMachineInfo
        let addedAt: Date
        var rows: [RemoteSession]?
        var lastOkAt: Date?
        /// 最近一次讀的結果是失敗（nil ＝ 最近一次成功、或還沒讀完過）。
        var failure: HerdrFailure?
        var failures = 0
        var lastStartedAt: Date?
        var inFlight = false
    }

    /// 照機器清單的順序。
    private(set) var machines: [Machine] = []
    /// 機器清單：nil ＝ 還沒讀過；讀過的話最近一次是成功還是失敗。
    private var listState: Result<Void, HerdrFailure>?
    private var listEverRead = false
    private var listStartedAt: Date?
    private var wantsMachineList = false

    public init() {}

    public var machineIds: [String] { machines.map(\.info.id) }

    // MARK: - 讀到東西

    public mutating func machinesRead(_ r: Result<[RemoteMachineInfo], HerdrFailure>, now: Date) {
        switch r {
        case .success(let list):
            listState = .success(())
            listEverRead = true
            wantsMachineList = false
            // 清單外的忘掉（正面證據：使用者在 herdr 裡移掉或關掉了）；新的從「讀取中」開始。
            machines = list.map { info in
                if var m = machines.first(where: { $0.info.id == info.id }) {
                    m.info = info
                    return m
                }
                return Machine(info: info, addedAt: now)
            }
        case .failure(let f):
            // ⚠️ 讀過的機器照留 —— 清單讀不到不等於那些機器不在了。
            listState = .failure(f)
        }
    }

    public mutating func agentsRead(machineId: String, _ r: Result<[RemoteSession], HerdrFailure>,
                                    now: Date) {
        // 清單外的 id（讀的時候那台還在、讀完已經被移掉）：不收。
        guard let i = machines.firstIndex(where: { $0.info.id == machineId }) else { return }
        machines[i].inFlight = false
        switch r {
        case .success(let rows):
            machines[i].rows = rows
            machines[i].lastOkAt = now
            machines[i].failure = nil
            machines[i].failures = 0
        case .failure(let f):
            machines[i].failure = f
            machines[i].failures += 1
            if f == .unknownMachine { wantsMachineList = true }
        }
    }

    // MARK: - 什麼時候讀

    public func machineListDue(now: Date) -> Bool {
        guard let started = listStartedAt else { return true }
        return wantsMachineList || now.timeIntervalSince(started) >= HerdrCommand.machineListInterval
    }

    public mutating func machineListStarted(now: Date) {
        listStartedAt = now
        wantsMachineList = false
    }

    /// 該讀的機器：沒在讀、而且離上次**開始**讀已經過了一個間隔（連續失敗時退避）。
    public func dueMachines(now: Date) -> [String] {
        machines.filter { m in
            guard !m.inFlight else { return false }
            guard let started = m.lastStartedAt else { return true }
            return now.timeIntervalSince(started) >= Self.interval(failures: m.failures)
        }.map(\.info.id)
    }

    public mutating func agentsStarted(machineId: String, now: Date) {
        guard let i = machines.firstIndex(where: { $0.info.id == machineId }) else { return }
        machines[i].lastStartedAt = now
        machines[i].inFlight = true
    }

    /// 正常 10 秒；連續失敗 n 次 → 10 × 2ⁿ，上限 60。連不上的機器不必每 10 秒等一次 15 秒的逾時。
    static func interval(failures: Int) -> TimeInterval {
        min(HerdrCommand.remoteInterval * pow(2, Double(min(failures, 6))), maxBackoff)
    }

    // MARK: - 要畫什麼

    public func view(now: Date) -> RemoteView {
        switch listState {
        case nil:
            return .hidden
        case .failure(.notInstalled):
            return .hidden
        case .failure(.serverNotRunning):
            return .notice("herdr 沒在跑 · 看不到遠端機器")
        case .failure(let f) where !listEverRead:
            return .notice("讀不到 herdr 的機器清單 · \(RemoteWords.reason(f))")
        default:
            break
        }
        if machines.isEmpty { return .notice("herdr 沒有連任何遠端機器") }
        return .machines(machines.map { card($0, now: now) })
    }

    private func card(_ m: Machine, now: Date) -> RemoteCard {
        func make(_ caption: String, warning: Bool, counts: [RemoteCount]? = nil,
                  dimmed: Bool = false, waiting: [RemoteSession] = [], note: String? = nil) -> RemoteCard {
            RemoteCard(id: m.info.id, label: m.info.label, caption: caption, warning: warning,
                       counts: counts, countsDimmed: dimmed, waiting: waiting, note: note)
        }
        guard let rows = m.rows, let ok = m.lastOkAt else {
            // 從沒讀到過
            if let f = m.failure { return make("還沒讀到 · \(RemoteWords.reason(f))", warning: true) }
            if now.timeIntervalSince(m.addedAt) < Self.loadingGrace { return make("讀取中", warning: false) }
            return make("還沒讀到", warning: true)
        }
        let age = now.timeIntervalSince(ok)
        if m.failure != nil {
            let caption = "連不上 · \(RemoteWords.ago(age))最後看到"
            guard age < Self.offlineCut else { return make(caption, warning: true) }
            return make(caption, warning: true, counts: Self.counts(rows), dimmed: true)
        }
        return make("\(rows.count) 個 · \(RemoteWords.ago(age))看到", warning: false,
                    counts: Self.counts(rows),
                    waiting: rows.filter { $0.status == .blocked },
                    note: rows.isEmpty ? "herdr 分頁裡沒有 Claude session" : nil)
    }

    static func counts(_ rows: [RemoteSession]) -> [RemoteCount] {
        RemoteStatus.allCases.compactMap { s in
            let n = rows.filter { $0.status == s }.count
            return n == 0 ? nil : RemoteCount(status: s, n: n, text: "\(n) \(RemoteWords.status(s))")
        }
    }
}

/// 這一區的措辭。判斷與措辭都在 Core（規矩 4），App 只照著畫。
public enum RemoteWords {

    /// 「剛剛」「5 秒前」「4 分前」「2 小時前」。負的（時鐘往回跳）當成剛剛。
    public static func ago(_ seconds: TimeInterval) -> String {
        let s = Int(max(0, seconds))
        switch s {
        case ..<5:    return "剛剛"
        case ..<60:   return "\(s) 秒前"
        case ..<3600: return "\(s / 60) 分前"
        default:      return "\(s / 3600) 小時前"
        }
    }

    /// 等你回覆那一列的兩段字：主名（標題，沒有就專案，都沒有就說沒有）、副名（有標題時才寫專案）。
    public static func waitingLabel(_ s: RemoteSession) -> (main: String, sub: String?) {
        if let t = s.title { return (t, s.project) }
        return (s.project ?? "（沒有名字）", nil)
    }

    public static func status(_ s: RemoteStatus) -> String {
        switch s {
        case .blocked: return "等你"
        case .working: return "執行"
        case .done:    return "完成"
        case .idle:    return "閒置"
        case .unknown: return "不明"
        }
    }

    public static func reason(_ f: HerdrFailure) -> String {
        switch f {
        case .notInstalled:     return "找不到 herdr"
        case .serverNotRunning: return "herdr 沒在跑"
        case .unknownMachine:   return "機器清單過期"
        case .incompatible:     return "herdr 的回應讀不懂"
        case .herdrError:       return "連不上"
        case .timedOut:         return "逾時"
        }
    }
}
