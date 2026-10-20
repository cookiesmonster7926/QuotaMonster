import Foundation
import QuotaMonsterCore

/// `--render-panel --demo-remote <狀態>` 的合成資料。
///
/// ⚠️ 只有**資料**是編的：狀態一律經 `RemoteTracker` 的公開 API 推進（讀到清單、讀到 session、讀失敗），
/// 畫面照 `RemoteTracker.view` 畫 —— 與真的 app 同一條路（CLAUDE.md：診斷要跟出貨路徑共用建構點）。
/// 機器名、專案、標題全部是編的，不是任何一台真的機器。
enum DemoRemote {

    static let states = ["live", "offline", "cut", "loading", "never", "empty", "server", "none", "two"]

    static func tracker(_ state: String, now: Date) -> RemoteTracker? {
        let win = RemoteMachineInfo(id: "aaaa1111", label: "WIN-DESKTOP")
        let lab = RemoteMachineInfo(id: "bbbb2222", label: "LAB-SERVER")
        let rows = [
            RemoteSession(title: "論文第三章校稿", project: "paper", status: .blocked),
            RemoteSession(title: "訓練 PPO 第二輪", project: "train-rl", status: .working),
            RemoteSession(title: "資料前處理腳本", project: "dataset", status: .done),
            RemoteSession(title: "實驗紀錄整理", project: "notebooks", status: .idle),
            RemoteSession(title: "環境設定", project: "env", status: .idle),
            RemoteSession(title: nil, project: "train-rl", status: .idle),
        ]
        func ago(_ s: TimeInterval) -> Date { now.addingTimeInterval(-s) }
        var t = RemoteTracker()
        switch state {
        case "live":
            t.machinesRead(.success([win]), now: ago(30))
            t.agentsRead(machineId: win.id, .success(rows), now: ago(3))
        case "offline":
            t.machinesRead(.success([win]), now: ago(600))
            t.agentsRead(machineId: win.id, .success(rows), now: ago(240))
            t.agentsRead(machineId: win.id, .failure(.timedOut), now: ago(5))
        case "cut":
            t.machinesRead(.success([win]), now: ago(7200))
            t.agentsRead(machineId: win.id, .success(rows), now: ago(3600))
            t.agentsRead(machineId: win.id, .failure(.herdrError(code: nil)), now: ago(5))
        case "loading":
            t.machinesRead(.success([win]), now: ago(2))
        case "never":
            t.machinesRead(.success([win]), now: ago(60))
            t.agentsRead(machineId: win.id, .failure(.timedOut), now: ago(10))
        case "empty":
            t.machinesRead(.success([win]), now: ago(30))
            t.agentsRead(machineId: win.id, .success([]), now: ago(3))
        case "server":
            t.machinesRead(.failure(.serverNotRunning), now: ago(3))
        case "none":
            t.machinesRead(.success([]), now: ago(3))
        case "two":
            t.machinesRead(.success([win, lab]), now: ago(600))
            t.agentsRead(machineId: win.id, .success(rows), now: ago(3))
            t.agentsRead(machineId: lab.id, .success(Array(rows.dropFirst(2))), now: ago(400))
            t.agentsRead(machineId: lab.id, .failure(.timedOut), now: ago(5))
        default:
            return nil
        }
        return t
    }
}
