import Foundation

/// 清理 statusline tee 的快取目錄。
///
/// **這是整個 Core 唯一會刪檔的東西。** 所以它的判斷極度保守：
/// 只認兩種明確是我們自己寫出來的檔名，其餘一概不碰。
///
/// 要清的兩種垃圾：
///   - `.tmp.<pid>` 孤兒 —— Claude Code 用 abort 取消執行中的 statusline script。
///     wrapper 有 trap 收 TERM/INT/HUP，但 SIGKILL 攔不到；實測 SIGKILL 會留下
///     一個寫到一半的暫存檔。
///   - 已經結束的 session 的快取檔 —— 那個 session 不會再寫，也沒人會來刪。
///
/// 目錄是 QuotaMonster 自己的（`~/Library/Application Support/QuotaMonster/`），
/// 不是 Claude Code 的，所以在這裡刪檔不會動到別人的東西。
public struct StatusLineCachePruner: Sendable {

    /// 暫存檔要活過的時間。statusline script 的實測執行時間是 20 ms 量級，
    /// 5 分鐘有四個數量級的餘裕 —— 寧可留著垃圾，也不要刪掉正在寫的檔案。
    public static let tempGrace: TimeInterval = 300

    /// session 快取的保留期。過了就代表那個 session 至少一天沒動靜了。
    public static let payloadRetention: TimeInterval = 24 * 3600

    public init() {}

    public func prune(directory: URL, now: Date) {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else { return }

        for name in names {
            let url = directory.appendingPathComponent(name)
            guard let limit = Self.retention(for: name),
                  let attrs = try? fm.attributesOfItem(atPath: url.path),
                  let mtime = attrs[.modificationDate] as? Date,
                  now.timeIntervalSince(mtime) > limit
            else { continue }
            // ⚠️ 只刪**一般檔案**。`removeItem` 是遞迴的，所以一個叫 `adir.json`
            // 的目錄會連同裡面的東西一起消失。我們自己只寫一般檔案，
            // 所以任何不是一般檔案的東西都不是我們的，一概不碰。
            guard (attrs[.type] as? FileAttributeType) == .typeRegular else { continue }
            try? fm.removeItem(at: url)
        }
    }

    /// 這個檔名是我們寫的嗎，要留多久。不是我們的就回 nil ——
    /// 回 nil 的意思是「連碰都不要碰」，不是「立刻刪」。
    static func retention(for name: String) -> TimeInterval? {
        if name.hasPrefix(".tmp.") { return tempGrace }
        if name.hasSuffix(".json") && !name.hasPrefix(".") { return payloadRetention }
        return nil
    }
}
