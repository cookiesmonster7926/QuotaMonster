import Foundation
import QuotaMonsterCore

/// 去 GitHub 問一次「有沒有新版」。
///
/// ### ⚠️ 這是整個 app 裡**唯一**一個會連網的檔案
/// 在這之前 `grep -rn URLSession Sources/` 是零命中，而 README 與 SECURITY.md
/// 都把那件事寫給使用者看、還附了讓他自己跑的 `grep`。所以：
/// - 網路呼叫只能在這裡。任何第二個地方出現 `URLSession` 都是一個要被擋下來的 PR。
/// - 使用者關掉 `checksForUpdates` 之後，這個檔案**一次都不會被呼叫**，
///   那個承諾就仍然成立。
///
/// ### ⚠️ 它不在 3 秒的刷新迴圈裡
/// `DataStore.refresh()` 每 3 秒跑一次，穩態 62.8 毫秒（規矩 47）。
/// 網路請求的延遲是它的幾百倍，而且會失敗 —— 放進去等於把一個
/// 「本機檔案掃描」的迴圈變成一個會被網路拖住的迴圈。
/// 這支自己有一個小時級的節奏（`UpdateCheck.interval`）。
@MainActor
final class ReleaseChecker {

    /// ⚠️ 寫死在這裡，不做成偏好。它是**這一份**程式碼要去問的那個 repo；
    /// 做成可調的只會讓「我的 app 去問了誰」變成一個沒有答案的問題。
    private static let endpoint = URL(
        string: "https://api.github.com/repos/cookiesmonster7926/QuotaMonster/releases/latest")!

    /// 逾時。⚠️ 選擇不是量測：它只要短到「使用者不會感覺到」，
    /// 而這支根本不在使用者等待的路徑上，所以寬鬆一點也無妨。
    private static let timeout: TimeInterval = 15

    private let home: URL
    /// ⚠️ **只活在記憶體**（規矩 20：抑制方向的觀測值不落地）。
    /// 丟掉它的代價只是每次開 app 多問一次。
    private var lastAttempt: Date?

    private(set) var status: UpdateStatus = .unknown(.notCheckedYet)
    private(set) var lastSuccess: Date?

    init(home: URL) {
        self.home = home
        self.lastSuccess = UpdateState.load(UpdateState.defaultURL(home: home))?.lastSuccess
    }

    /// 這一刻該不該去問。判準在 Core。
    func shouldCheck(now: Date) -> Bool {
        UpdateCheck.shouldCheck(lastAttempt: lastAttempt, now: now)
    }

    /// 去問一次。**呼叫端負責先問 `shouldCheck` 與使用者的偏好。**
    func check(current: ReleaseVersion, now: Date) async {
        lastAttempt = now
        var request = URLRequest(url: Self.endpoint, timeoutInterval: Self.timeout)
        // ⚠️ 明確要求 GitHub 的 JSON 版本 —— 不指定的話它有權改預設格式。
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                status = .unknown(.unreadable); return
            }
            // 〔實測 2026-09-23〕未認證是 60 次/小時/IP（`x-ratelimit-limit: 60`）。
            // 用完之後 GitHub 回 403 或 429 —— 那是「問不到」，**不是**「沒有新版」。
            if http.statusCode == 403 || http.statusCode == 429 {
                status = .unknown(.rateLimited); return
            }
            guard http.statusCode == 200 else { status = .unknown(.unreadable); return }

            // ⚠️ 用 `JSONSerialization` 不用 `Codable`（第二節拒絕 6）：
            // 這是一個沒有契約的外部格式，未知的 key 必須無害、缺 key 必須容忍。
            guard let d = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let tag = d["tag_name"] as? String,
                  let url = d["html_url"] as? String else {
                status = .unknown(.unreadable); return
            }
            status = UpdateStatus.from(
                latestTag: tag, current: current,
                // 缺 key 當成 false —— GitHub 一直都有給這兩個欄位，
                // 但一個沒有契約的格式不該讓我們因為少一個 key 就整個壞掉。
                isDraft: d["draft"] as? Bool ?? false,
                isPrerelease: d["prerelease"] as? Bool ?? false,
                url: url)

            // ⚠️ 只有**真的問到並看懂**才算成功。被限流、解不出來都不算 ——
            // 算進去的話，「已經三天問不到」那句話永遠不會出現。
            switch status {
            case .available, .upToDate:
                lastSuccess = now
                UpdateState.save(UpdateState(lastSuccess: now),
                                 to: UpdateState.defaultURL(home: home))
            case .unknown:
                break
            }
        } catch {
            // ⚠️ 連不上就是連不上。**不可以**在這裡塌縮成「沒有新版」。
            status = .unknown(.offline)
        }
    }
}
