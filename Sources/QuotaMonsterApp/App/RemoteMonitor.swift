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
        Self.sweepScratch(home: home, olderThan: 60)
        poll()
        let t = Timer(timeInterval: Self.tick, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        // .common：選單追蹤（面板開著）時也要走。
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// 停下來而且忘掉 —— 下次打開從「讀取中」開始，不畫關掉之前的舊資料。
    /// 還在途的 herdr 收掉（SIGTERM），就算它回來了結果也會被丟掉（`generation` 對不上）。
    /// 結束 app 時也走這裡（`DataStore.stop()`）—— code review：原本不停，結束時在途的 herdr 沒人收。
    func stop() {
        timer?.invalidate()
        timer = nil
        running.terminateAll()
        tracker = RemoteTracker()
        generation += 1
        reportedMissing = false
        onChange?(tracker)
    }

    private var generation = 0
    private var reportedMissing = false
    /// 在途的 herdr 行程，`stop()` 時收掉。
    private let running = RunningProcesses()

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
                let run = await Self.run(exe, HerdrCommand.machineList, home: home, running: running)
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
                let run = await Self.run(exe, argv, home: home, running: running)
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
    /// 目錄 0700、檔案 0600：裡面是別台機器的分頁標題與目錄名（code review：原本跟著 umask 是 0755／0644）。
    /// app 在 herdr 跑到一半時被結束或當掉，`defer` 不會跑 —— 殘留的由下次 `start()` 的 `sweepScratch` 清掉。
    nonisolated static func run(_ exe: URL, _ args: [String], home: URL, running: RunningProcesses? = nil,
                                timeout: TimeInterval = HerdrCommand.timeout) async -> HerdrRun {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                cont.resume(returning: runBlocking(exe, args, home: home, running: running, timeout: timeout))
            }
        }
    }

    nonisolated static func scratchRoot(home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support/QuotaMonster/herdr")
    }

    /// 刪掉上一次執行留下的暫存資料夾（app 在 herdr 跑到一半時被結束、當掉）。
    /// 只刪超過 `olderThan` 秒的：同時有另一個行程（例如 `--probe-remote`）正在用的那幾個不碰。
    /// 這個資料夾只有這個 app 寫。
    nonisolated static func sweepScratch(home: URL, olderThan age: TimeInterval) {
        let fm = FileManager.default
        let root = scratchRoot(home: home)
        guard let items = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey])
        else { return }
        let cutoff = Date().addingTimeInterval(-age)
        for u in items {
            let m = (try? u.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let m, m < cutoff { try? fm.removeItem(at: u) }
        }
    }

    nonisolated private static func runBlocking(_ exe: URL, _ args: [String], home: URL,
                                                running: RunningProcesses?,
                                                timeout: TimeInterval) -> HerdrRun {
        let fm = FileManager.default
        let dir = scratchRoot(home: home).appendingPathComponent(UUID().uuidString)
        let outURL = dir.appendingPathComponent("out")
        let errURL = dir.appendingPathComponent("err")
        defer { try? fm.removeItem(at: dir) }
        let privateFile: [FileAttributeKey: Any] = [.posixPermissions: 0o600]
        guard (try? fm.createDirectory(at: dir, withIntermediateDirectories: true,
                                       attributes: [.posixPermissions: 0o700])) != nil,
              fm.createFile(atPath: outURL.path, contents: nil, attributes: privateFile),
              fm.createFile(atPath: errURL.path, contents: nil, attributes: privateFile),
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
        running?.add(p)
        defer { running?.remove(p) }
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

/// 在途的 herdr 行程。背景執行緒加、減，主執行緒 `stop()` 時全部收掉 —— 所以要鎖。
final class RunningProcesses: @unchecked Sendable {
    private let lock = NSLock()
    private var procs: [ObjectIdentifier: Process] = [:]

    func add(_ p: Process) { lock.withLock { procs[ObjectIdentifier(p)] = p } }
    func remove(_ p: Process) { lock.withLock { _ = procs.removeValue(forKey: ObjectIdentifier(p)) } }

    /// SIGTERM 每一個還在跑的。各自的 `runBlocking` 會等到它結束、照常刪暫存資料夾。
    func terminateAll() {
        let all = lock.withLock { Array(procs.values) }
        for p in all where p.isRunning { p.terminate() }
    }
}
