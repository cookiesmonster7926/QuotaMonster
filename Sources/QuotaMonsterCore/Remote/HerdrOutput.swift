import Foundation

/// 執行一次 herdr 的結果（App 層跑子行程，交給這裡判斷）。
public struct HerdrRun: Sendable {
    /// nil ＝ 沒有正常結束（逾時被收掉、或根本沒啟動）。
    public let exitCode: Int32?
    public let stdout: Data
    public let stderr: Data
    /// 超過 `HerdrCommand.timeout` 被收掉。
    public let timedOut: Bool
    /// 找不到執行檔或啟動失敗。
    public let launchFailed: Bool

    public init(exitCode: Int32?, stdout: Data, stderr: Data, timedOut: Bool, launchFailed: Bool) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.timedOut = timedOut
        self.launchFailed = launchFailed
    }
}

/// 一台遠端機器（herdr 的 machine list 裡 enabled 的那些）。
public struct RemoteMachineInfo: Equatable, Sendable {
    /// `--machine` 要的 id（已經過白名單）。
    public let id: String
    /// 給人看的名字。
    public let label: String

    public init(id: String, label: String) {
        self.id = id
        self.label = label
    }
}

/// herdr 的 `agent_status`。宣告順序就是面板計數的順序（要你動手的排前面）。
public enum RemoteStatus: Equatable, Sendable, CaseIterable {
    case blocked, working, done, idle
    /// 不認得的值、或沒有這個欄位。⚠️ **不是 idle** —— 沒看到不等於閒著（規矩 1）。
    case unknown
}

/// 遠端的一個 Claude session（herdr 給得出的那幾格）。
public struct RemoteSession: Equatable, Sendable {
    /// 分頁標題（`terminal_title_stripped`）。nil ＝ 沒有。
    public let title: String?
    /// cwd 的最後一段。
    public let project: String?
    public let status: RemoteStatus

    public init(title: String?, project: String?, status: RemoteStatus) {
        self.title = title
        self.project = project
        self.status = status
    }
}

/// 讀不到的原因。⚠️ 每一種畫面上說的話不一樣（`RemoteWords.reason`），不可以併成「讀不到」。
public enum HerdrFailure: Error, Equatable, Sendable {
    /// 找不到 herdr 或啟動不了 → 整區不畫（沒裝 herdr 的人不該看到這一區）。
    case notInstalled
    /// 本機的 herdr server 沒在跑：exit 1、`error.code == "server_not_running"`〔實測〕。
    case serverNotRunning
    /// `--machine` 的 id 不認得 —— 機器清單過期了。
    case unknownMachine
    /// exit 0 但讀不懂，或 herdr 說 protocol 不合 —— 版本不相容。**不是「沒有 session」。**
    case incompatible
    /// 其他 herdr 錯誤（連不上遠端多半是這種）。code ＝ herdr 自己的錯誤碼，沒有就是 nil。
    case herdrError(code: String?)
    /// 超過 `HerdrCommand.timeout`。
    case timedOut
}

/// 把 herdr 的輸出變成資料，或說出為什麼不行。全部是純函式。
///
/// ⚠️ 用 `JSONSerialization` ＋ `as?`，不用 Codable：外部的 JSON 少一個欄位不可以讓整份讀不出來
/// （這個 repo 讀所有外部資料都是這樣）。
public enum HerdrOutput {

    /// 字串的上限（標題、label）。面板一行放不下這麼多，這只是擋住異常的輸入。
    public static let maxText = 200

    public static func machines(_ run: HerdrRun) -> Result<[RemoteMachineInfo], HerdrFailure> {
        if let f = failure(run) { return .failure(f) }
        guard let list = (try? JSONSerialization.jsonObject(with: run.stdout)) as? [[String: Any]] else {
            return .failure(.incompatible)
        }
        return .success(list.compactMap { m in
            // 只收 enabled 的；enabled 不是 true（含沒有這個欄位）就不收 —— 使用者在 herdr 裡關掉的機器不去連。
            guard m["enabled"] as? Bool == true,
                  let id = m["id"] as? String, HerdrCommand.isValidMachineId(id) else { return nil }
            let label = (m["label"] as? String).flatMap { clean($0, max: maxText) }
                ?? String(id.prefix(8))
            return RemoteMachineInfo(id: id, label: label)
        })
    }

    public static func agents(_ run: HerdrRun) -> Result<[RemoteSession], HerdrFailure> {
        if let f = failure(run) { return .failure(f) }
        guard let root = (try? JSONSerialization.jsonObject(with: run.stdout)) as? [String: Any],
              let result = root["result"] as? [String: Any],
              let agents = result["agents"] as? [[String: Any]] else {
            return .failure(.incompatible)
        }
        return .success(agents.compactMap { a in
            guard a["agent"] as? String == "claude" else { return nil }
            return RemoteSession(
                title: (a["terminal_title_stripped"] as? String).flatMap { clean($0, max: maxText) },
                project: project(cwd: a["cwd"] as? String),
                status: status(a["agent_status"] as? String))
        })
    }

    static func status(_ raw: String?) -> RemoteStatus {
        switch raw {
        case "working": return .working
        case "blocked": return .blocked
        case "done":    return .done
        case "idle":    return .idle
        default:        return .unknown
        }
    }

    /// 成功（exit 0、沒逾時）回 nil；否則是哪一種失敗。
    ///
    /// 順序：啟動不了 → 逾時 → exit code。逾時被收掉的行程 exit code 是訊號的那一個，不可以拿來判斷。
    static func failure(_ run: HerdrRun) -> HerdrFailure? {
        if run.launchFailed { return .notInstalled }
        if run.timedOut { return .timedOut }
        guard let code = run.exitCode else { return .herdrError(code: nil) }
        if code == 0 { return nil }
        let err = String(decoding: run.stderr, as: UTF8.self)
        if err.contains("unknown machine") { return .unknownMachine }
        let herdrCode = ((try? JSONSerialization.jsonObject(with: run.stderr)) as? [String: Any])
            .flatMap { $0["error"] as? [String: Any] }
            .flatMap { $0["code"] as? String }
        switch herdrCode {
        case "server_not_running": return .serverNotRunning
        case let c? where c.contains("protocol"): return .incompatible
        default: return .herdrError(code: herdrCode)
        }
    }

    /// 給人看的字串：剝掉控制字元（C0、DEL、C1）與頭尾空白，截到 `max` 個字。剝完是空的回 nil。
    ///
    /// 遠端的標題與機器名是**別人的機器**給的字串 —— 終端機的跳脫序列、換行都可能在裡面。
    public static func clean(_ s: String, max: Int) -> String? {
        let kept = s.unicodeScalars.filter { u in
            !(u.value < 0x20 || (0x7F...0x9F).contains(u.value))
        }
        let t = String(String.UnicodeScalarView(kept)).trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        return t.count > max ? String(t.prefix(max)) : t
    }

    /// cwd 的最後一段。`/` 與 `\` 都認（遠端可能是 Windows）；結尾的分隔符不算。
    public static func project(cwd: String?) -> String? {
        guard let cwd else { return nil }
        let last = cwd.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last
        return last.flatMap { clean(String($0), max: maxText) }
    }
}
