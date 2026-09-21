import Testing
import Foundation
@testable import QuotaMonsterCore

/// 一個 session 的 subagent 目錄在 `~/.claude/projects/<slug>/<sessionId>/`。
/// 但實測 11 個 session 目錄中有 1 個**同時存在於兩個 project slug 底下**。
/// 判別依據是同層有沒有 `<sessionId>.jsonl` 這個兄弟檔。
@Suite("SessionDirectoryResolver")
struct SessionDirectoryResolverTests {

    let resolver = SessionDirectoryResolver()

    @Test("找得到有兄弟 transcript 的那個目錄")
    func resolvesTheDirectoryWithASiblingTranscript() throws {
        let root = try Fixture.projectsRoot()
        let found = try #require(resolver.resolve(sessionId: Fixture.agentSessionId,
                                                  projectsRoot: root))
        #expect(found.lastPathComponent == Fixture.agentSessionId)
        #expect(found.deletingLastPathComponent().lastPathComponent == "-tmp-fixture-project")
    }

    @Test("同一個 sessionId 出現在兩個 slug 下時，選有兄弟 transcript 的那個")
    func disambiguatesBySiblingTranscript() throws {
        let root = try Fixture.projectsRoot()
        // 兩個 slug 底下都有這個 sessionId 目錄，只有一個有 <sessionId>.jsonl
        let other = root.appendingPathComponent("-tmp-other-project/\(Fixture.agentSessionId)")
        #expect(FileManager.default.fileExists(atPath: other.path))

        let found = try #require(resolver.resolve(sessionId: Fixture.agentSessionId,
                                                  projectsRoot: root))
        #expect(found.path != other.path)
    }

    @Test("找不到時回傳 nil，不丟錯")
    func unknownSessionYieldsNil() throws {
        let root = try Fixture.projectsRoot()
        #expect(resolver.resolve(sessionId: "no-such-session", projectsRoot: root) == nil)
    }

    @Test("projects 根目錄不存在時回傳 nil")
    func missingRootYieldsNil() {
        let root = URL(fileURLWithPath: "/tmp/nope-\(UUID().uuidString)")
        #expect(resolver.resolve(sessionId: Fixture.agentSessionId, projectsRoot: root) == nil)
    }

    @Test("同時回報協調者 transcript 的位置 —— 一般 agent 要靠它配對 toolUseId")
    func alsoReportsTheOrchestratorTranscript() throws {
        let root = try Fixture.projectsRoot()
        let located = try #require(resolver.locate(sessionId: Fixture.agentSessionId,
                                                   projectsRoot: root))
        #expect(located.transcript.lastPathComponent == "\(Fixture.agentSessionId).jsonl")
        #expect(FileManager.default.fileExists(atPath: located.transcript.path))
        #expect(located.subagents.lastPathComponent == "subagents")
    }

    @Test("sessionId 是磁碟上的字串 —— 不可以讓它決定我們讀哪個目錄")
    func pathLikeSessionIdIsRejected() throws {
        let root = try Fixture.projectsRoot()
        // 下面每一個都是合法的 JSON 字串值，而 appendingPathComponent 會照單全收。
        for hostile in ["../../../etc", "a/b", "..", "/absolute", ""] {
            #expect(SessionDirectoryResolver().locate(sessionId: hostile,
                                                      projectsRoot: root) == nil)
        }
    }

    @Test("正常的 sessionId 形狀仍然過得去")
    func ordinarySessionIdsStillResolve() {
        // 第二個是另一組規律假值：跟第一個不同的十六進位字元，
        // 但一樣是 8-4-4-4-12、version 4、variant 8 的 UUID 形狀。
        // ⚠️ 不可以貼真機上的 session id —— 那是個人痕跡。
        #expect(SessionDirectoryResolver.isPlausibleSessionId(Fixture.agentSessionId))
        #expect(SessionDirectoryResolver.isPlausibleSessionId(
            "bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb"))
    }
}
