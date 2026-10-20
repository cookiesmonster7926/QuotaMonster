import Foundation
import QuotaMonsterCore

/// 問 herdr 遠端機器上的 session。判斷全部在 `RemoteTracker`／`HerdrOutput`（Core），這裡只有「怎麼執行」。
///
/// ⚠️ **刻意不在 `refresh()` 裡**（與 `ReleaseChecker` 同一個理由）：`refresh()` 3 秒一拍、穩態 62.8 毫秒
/// （規矩 47），而遠端一次 2–5 秒〔實測，見 `HerdrCommand.timeout`〕。這裡自己一個 2 秒的拍子，
/// 每拍只問 `RemoteTracker` 哪些到期了；每次執行都在背景執行緒，主執行緒不等。
///
/// ⚠️ 只有偏好打開時才存在（`DataStore.setShowsRemoteSessions`）。關掉 → `stop()`，一次 herdr 都不再執行。
@MainActor
final class RemoteMonitor {

    private(set) var tracker = RemoteTracker()
    /// 讀到新東西時叫一次（DataStore 拿去更新面板）。
    var onChange: ((RemoteTracker) -> Void)?

    private let home: URL
    private var timer: Timer?
    /// 每拍多久看一次哪些到期。實際讀的間隔由 `RemoteTracker` 決定（10 秒、退避到 60 秒）。
    static let tick: TimeInterval = 2

    init(home: URL) { self.home = home }

    func start() {
        guard timer == nil else { return }
        poll()
        let t = Timer(timeInterval: Self.tick, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        // .common：選單追蹤（面板開著）時也要走。
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// 停下來而且忘掉 —— 下次打開從「讀取中」開始，不畫關掉之前的舊資料。
    /// 還在途的那幾次讀完會被丟掉（`generation` 對不上）。
    func stop() {
        timer?.invalidate()
        timer = nil
        tracker = RemoteTracker()
        generation += 1
        reportedMissing = false
        onChange?(tracker)
    }

    private var generation = 0
    private var reportedMissing = false

    /// 第一個存在而且可執行的候選路徑。⚠️ 不靠 PATH：GUI app 的 PATH 沒有 ~/.local/bin。
    private var executable: URL? {
        HerdrCommand.candidatePaths(home: home)
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// 這一拍該讀的都啟動，**不等它們**。
    func poll() {
        let now = Date()
        guard let exe = executable else {
            // 沒裝 herdr：整區不畫（`RemoteView.hidden`）。每拍都看一次（只是三次 stat），
            // 裝了就接得上；但同一件事只通知一次，面板不必每 2 秒重畫。
            if !reportedMissing {
                reportedMissing = true
                tracker.machinesRead(.failure(.notInstalled), now: now)
                onChange?(tracker)
            }
            return
        }
        if reportedMissing {
            // 剛裝好：從頭來，機器清單馬上讀
            reportedMissing = false
            tracker = RemoteTracker()
        }
        let gen = generation
        if tracker.machineListDue(now: now) {
            tracker.machineListStarted(now: now)
            Task {
                let run = await Self.run(exe, HerdrCommand.machineList, home: home)
                guard gen == generation else { return }
                tracker.machinesRead(HerdrOutput.machines(run), now: Date())
                onChange?(tracker)
                // 清單剛讀到：新的機器不等下一拍
                pollMachines(exe, gen: gen)
            }
        }
        pollMachines(exe, gen: gen)
    }

    private func pollMachines(_ exe: URL, gen: Int) {
        let now = Date()
        for id in tracker.dueMachines(now: now) {
            // 白名單過不了的 id 根本進不了 tracker（`HerdrOutput.machines` 已經擋掉）；這裡再擋一次是因為
            // 這一行就是「把字串交給另一個程式」的那一刻。
            guard let argv = HerdrCommand.agentList(machineId: id) else { continue }
            tracker.agentsStarted(machineId: id, now: now)
            Task {
                let run = await Self.run(exe, argv, home: home)
                guard gen == generation else { return }
                tracker.agentsRead(machineId: id, HerdrOutput.agents(run), now: Date())
                onChange?(tracker)
            }
        }
    }

    /// 執行一次 herdr，最多等 `HerdrCommand.timeout`。不丟錯：所有失敗都在 `HerdrRun` 裡。
    ///
    /// ⚠️ **stdout／stderr 寫到暫存檔，不用 pipe。** herdr 背後有常駐的 ssh（ControlMaster）。
    /// 〔實測 2026-10-20〕那些 ssh 是 herdr server 的子行程、不是這次 CLI 的，用 pipe 讀三次都 2 秒內回來；
    /// 但「這次 CLI 自己把 ssh 拉起來」的冷啟動沒量到 —— 那種情況下 ssh 會繼承 pipe 的寫入端，
    /// 讀到 EOF 要等它結束（ControlPersist 600 秒）。檔案沒有這個問題：行程結束就讀，誰還拿著都無所謂。
    ///
    /// ⚠️ 暫存檔放在**自己的** Application Support 底下（`herdr/<UUID>/`，讀完整個刪掉），不放 `$TMPDIR`：
    /// SECURITY.md 第 2 節對使用者說「只寫 `~/Library/Application Support/QuotaMonster/` 底下」。
    nonisolated static func run(_ exe: URL, _ args: [String], home: URL,
                                timeout: TimeInterval = HerdrCommand.timeout) async -> HerdrRun {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                cont.resume(returning: runBlocking(exe, args, home: home, timeout: timeout))
            }
        }
    }

    nonisolated static func scratchRoot(home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support/QuotaMonster/herdr")
    }

    nonisolated private static func runBlocking(_ exe: URL, _ args: [String], home: URL,
                                                timeout: TimeInterval) -> HerdrRun {
        let fm = FileManager.default
        let dir = scratchRoot(home: home).appendingPathComponent(UUID().uuidString)
        let outURL = dir.appendingPathComponent("out")
        let errURL = dir.appendingPathComponent("err")
        defer { try? fm.removeItem(at: dir) }
        guard (try? fm.createDirectory(at: dir, withIntermediateDirectories: true)) != nil,
              fm.createFile(atPath: outURL.path, contents: nil),
              fm.createFile(atPath: errURL.path, contents: nil),
              let out = try? FileHandle(forWritingTo: outURL),
              let err = try? FileHandle(forWritingTo: errURL) else {
            return HerdrRun(exitCode: nil, stdout: Data(), stderr: Data(), timedOut: false, launchFailed: true)
        }
        defer { try? out.close(); try? err.close() }

        let p = Process()
        p.executableURL = exe
        p.arguments = args
        // 不繼承任何輸入：沒人回答的互動提示不可以讓它掛著（OSAScriptNotifier 同一條）。
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = out
        p.standardError = err
        let done = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in done.signal() }
        do { try p.run() } catch {
            return HerdrRun(exitCode: nil, stdout: Data(), stderr: Data(), timedOut: false, launchFailed: true)
        }
        var timedOut = false
        if done.wait(timeout: .now() + timeout) == .timedOut {
            timedOut = true
            p.terminate()
            // SIGTERM 收不掉就算了 —— 不在這裡無限等；Foundation 之後自己收屍。
            _ = done.wait(timeout: .now() + 2)
        }
        let stdout = (try? Data(contentsOf: outURL)) ?? Data()
        let stderr = (try? Data(contentsOf: errURL)) ?? Data()
        return HerdrRun(exitCode: p.isRunning ? nil : p.terminationStatus,
                        stdout: stdout, stderr: stderr, timedOut: timedOut, launchFailed: false)
    }
}
