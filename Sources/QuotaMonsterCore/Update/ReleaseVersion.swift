import Foundation

/// 一個 `major.minor.patch` 版本號。
///
/// ### ⚠️ 存在的唯一理由：不可以用字串比大小
/// `"0.10.0" < "0.9.0"` 在字典序上是**真**的。照字串比，0.10.0 發布之後
/// 所有 0.9.x 的使用者會被告知「你已經是最新的」—— 而那是一個**安靜的**錯誤，
/// 沒有人會回報，因為畫面上看起來完全正常。
///
/// ⚠️ **解不出來回 nil，不猜。** tag 上可能出現 `nightly`、`v1.2`、`0.3.0-beta`，
/// 而「猜一個」的後果是拿一個編造的版本去跟真的比大小。
public struct ReleaseVersion: Equatable, Comparable, Sendable {

    public let major: Int
    public let minor: Int
    public let patch: Int

    /// - Parameter raw: GitHub 的 `tag_name`（`v0.3.0`）或 Info.plist 的
    ///   `CFBundleShortVersionString`（`0.3.0`）。`v` 前綴可有可無。
    public init?(_ raw: String) {
        // ⚠️ 不 trim：`"0.3.0 "` 這種帶空白的值代表上游出了別的問題，
        // 安靜地修好它會讓那個問題永遠不被發現。
        let body = raw.hasPrefix("v") ? String(raw.dropFirst()) : raw
        let parts = body.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var out: [Int] = []
        for p in parts {
            // ⚠️ 只收純數字，而且不收前導零（`00.3.0` 不是合法 semver）。
            // `Int(_:)` 自己會吃掉 `-1` 與 `+1`，所以不能只靠它。
            guard !p.isEmpty, p.allSatisfy({ $0.isASCII && $0.isNumber }),
                  p == "0" || !p.hasPrefix("0"),
                  let n = Int(p) else { return nil }
            out.append(n)
        }
        (major, minor, patch) = (out[0], out[1], out[2])
    }

    /// 面板要印的形式。**不帶 `v`** —— 那是 tag 的慣例，不是版本號的一部分。
    public var text: String { "\(major).\(minor).\(patch)" }

    public static func < (a: ReleaseVersion, b: ReleaseVersion) -> Bool {
        (a.major, a.minor, a.patch) < (b.major, b.minor, b.patch)
    }
}
