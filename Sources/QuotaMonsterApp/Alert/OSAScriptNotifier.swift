import AppKit
import QuotaMonsterCore

/// 通知中心／鎖定畫面那條副本通道。
///
/// 這是唯一進得了通知中心歷史與鎖定畫面的通道（NSPanel 做不到這兩件事）。
/// 代價是署名永遠顯示成「指令碼編輯器」—— 那個身分由 StandardAdditions 指派給
/// 任何由 `/usr/bin/osascript` 主持的腳本，唯一的改法是成為自己註冊的 app，
/// 而 Stage 0 已經證實這台機器上做不到（自建 applet 實測回 `-10814`，一則都沒送出）。
///
/// ⚠️ **參數陣列不在這裡組，在 `OSAScriptCommand`（Core，有測試）。**
/// 這個檔案只剩「怎麼啟動」—— 那一整段 `--` 為什麼是載重的、它到底守哪一格，
/// 都搬到判斷發生的地方去了。這裡放不住那種知識：`QuotaMonsterApp`
/// 沒有測試 target。
@MainActor
enum OSAScriptNotifier {

    /// 看門狗。實測一次完整生命週期約 92ms，SIGTERM 300ms 內收得掉。
    static let watchdog: TimeInterval = 10

    static func post(body: String, subtitle: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = OSAScriptCommand.arguments(body: body, subtitle: subtitle)
        // 不繼承任何 fd：沒人讀的 pipe 會在 64KB 之後把子行程卡死。
        //
        // ⚠️ `standardInput` 那一行**還會防掛**，不只是整潔：〔實測〕探測時
        // 有一個案例（osascript 的 `-i` 互動模式）真的掛滿 30 秒，
        // 補上 stdin 重導之後立刻正常。
        p.standardInput  = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        p.standardError  = FileHandle.nullDevice

        // 失敗就算了 —— NSPanel 才是主通道，這只是副本。
        do { try p.run() } catch { return }

        // **絕不 waitUntilExit()。** spawn 只要 0.45ms，但完整生命週期 92ms，
        // 在主執行緒上看得見。Foundation 自己會收屍，不必手動 reap。
        DispatchQueue.global().asyncAfter(deadline: .now() + watchdog) {
            if p.isRunning { p.terminate() }
        }
        // 離開 0 只代表「我們問了」，不代表「送到了」。不要用它當條件。
        //
        // ⚠️〔實測〕反過來也一樣，而且更嚴重：**非零離開碼不代表 payload 沒執行。**
        // 注入成功時 osascript 反而回 1（argv 被 getopt 吃掉一格，
        // run handler 之後才報 `Can't get item 3 of …`）—— 一次成功的 RCE
        // 藏在一則錯誤訊息底下。所以驗證那條防線只能看副作用，不能看離開碼。
    }

}
