import Testing
import Foundation
@testable import QuotaMonsterCore

/// 快取目錄會長出兩種垃圾：
///   - `.tmp.<pid>` 孤兒 —— Claude Code 用 abort 取消執行中的 statusline script，
///     收到 SIGKILL 時 wrapper 的 trap 來不及跑。實測確認會留下。
///   - 已經結束的 session 的快取檔 —— 沒人會再來刪它。
///
/// 這是**整個 Core 唯一會刪檔的東西**，所以它不碰什麼比它刪什麼更需要被釘住。
@Suite("StatusLineCachePruner")
struct StatusLineCachePrunerTests {

    let pruner = StatusLineCachePruner()
    let now = Fixture.now

    /// 建一個暫時目錄，裡面放指定檔名與年齡的檔案。
    func directory(_ files: [(name: String, age: TimeInterval)]) throws -> URL {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("qm-prune-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        for f in files {
            let u = dir.appendingPathComponent(f.name)
            try Data("{}".utf8).write(to: u)
            try fm.setAttributes([.modificationDate: now.addingTimeInterval(-f.age)],
                                 ofItemAtPath: u.path)
        }
        return dir
    }

    func names(_ dir: URL) -> Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
    }

    @Test("超過 5 分鐘的 .tmp.* 孤兒要刪掉 —— SIGKILL 會留下它們")
    func staleTempFilesAreRemoved() throws {
        let dir = try directory([(".tmp.4242", 600)])
        pruner.prune(directory: dir, now: now)
        #expect(names(dir).isEmpty)
    }

    @Test("5 分鐘內的 .tmp.* 不可刪 —— 那可能是正在寫的")
    func freshTempFilesSurvive() throws {
        let dir = try directory([(".tmp.4242", 30)])
        pruner.prune(directory: dir, now: now)
        #expect(names(dir) == [".tmp.4242"])
    }

    @Test("超過 24 小時的 session 快取要刪掉")
    func staleSessionCachesAreRemoved() throws {
        let dir = try directory([("11111111-1111-4111-8111-111111111111.json", TimeInterval(25 * 3600))])
        pruner.prune(directory: dir, now: now)
        #expect(names(dir).isEmpty)
    }

    @Test("24 小時內的 session 快取要留著")
    func recentSessionCachesSurvive() throws {
        let dir = try directory([("11111111-1111-4111-8111-111111111111.json", TimeInterval(23 * 3600))])
        pruner.prune(directory: dir, now: now)
        #expect(names(dir).count == 1)
    }

    @Test("不是我們寫的檔案一概不碰，再舊也不碰")
    func foreignFilesAreNeverTouched() throws {
        let dir = try directory([
            ("README.md", TimeInterval(400 * 86400)),
            ("notes.txt", TimeInterval(400 * 86400)),
            ("something.json.bak", TimeInterval(400 * 86400)),
            (".DS_Store", TimeInterval(400 * 86400)),
        ])
        pruner.prune(directory: dir, now: now)
        #expect(names(dir).count == 4)
    }

    @Test("名字叫 *.json 的目錄不可以被遞迴刪掉")
    func directoriesAreNeverRemoved() throws {
        let fm = FileManager.default
        let dir = try directory([])
        let trap = dir.appendingPathComponent("adir.json")
        try fm.createDirectory(at: trap, withIntermediateDirectories: true)
        let inside = trap.appendingPathComponent("important.txt")
        try Data("不可以不見".utf8).write(to: inside)
        try fm.setAttributes([.modificationDate: now.addingTimeInterval(-99 * 86400)],
                             ofItemAtPath: trap.path)

        pruner.prune(directory: dir, now: now)

        #expect(fm.fileExists(atPath: trap.path))
        #expect(fm.fileExists(atPath: inside.path))
    }

    @Test("目錄不存在時什麼都不做，不丟錯")
    func missingDirectoryIsHarmless() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("qm-not-here-\(UUID().uuidString)")
        pruner.prune(directory: dir, now: now)          // 不可 crash
        #expect(!FileManager.default.fileExists(atPath: dir.path))
    }

    @Test("一次清掉該清的，留下該留的")
    func prunesOnlyWhatItShould() throws {
        let dir = try directory([
            (".tmp.1", 600),                                              // 刪：孤兒
            (".tmp.2", 10),                                               // 留：正在寫
            ("11111111-1111-4111-8111-111111111111.json", 30),            // 留：活的
            ("22222222-2222-4222-8222-222222222222.json", TimeInterval(48 * 3600)),     // 刪：太舊
            ("_unkeyed.json", 30),                                        // 留：活的
            ("keep-me.txt", TimeInterval(99 * 86400)),                                  // 留：不是我們的
        ])
        pruner.prune(directory: dir, now: now)
        #expect(names(dir) == [".tmp.2",
                               "11111111-1111-4111-8111-111111111111.json",
                               "_unkeyed.json",
                               "keep-me.txt"])
    }
}
