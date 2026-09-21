import Testing
import Foundation
@testable import QuotaMonsterCore

/// `agent-<id>.meta.json` 是約 200 bytes、寫一次就不動的 sidecar。
/// 實測 187 個檔案共有 **5 種不同的 key 組合**，所以必要欄位只能有三個：
/// agentType / description / spawnDepth。其餘全部 optional，未知 key 必須無害。
@Suite("AgentMeta")
struct AgentMetaTests {

    let reader = AgentMetaReader()

    func meta(_ name: String) throws -> AgentMeta {
        let base = try Fixture.projectsRoot()
            .appendingPathComponent("-tmp-fixture-project/\(Fixture.agentSessionId)/subagents")
        return try #require(reader.read(base.appendingPathComponent("\(name).meta.json")))
    }

    @Test("agentId 來自檔名，不是檔案內容 —— meta.json 裡根本沒有這個欄位")
    func agentIdComesFromFilename() throws {
        #expect(try meta("agent-plain1").agentId == "plain1")
    }

    @Test("深度 1 的一般 agent 有 toolUseId、沒有 parentAgentId")
    func depthOnePlainAgent() throws {
        let m = try meta("agent-plain1")
        #expect(m.toolUseId == "toolu_PLAIN1")
        #expect(m.parentAgentId == nil)
        #expect(m.spawnDepth == 1)
        #expect(m.isWorkflowAgent == false)
    }

    @Test("深度 2 的一般 agent 兩個欄位都有")
    func depthTwoPlainAgent() throws {
        let m = try meta("agent-plain2")
        #expect(m.toolUseId == "toolu_CHILD")
        #expect(m.parentAgentId == "plain1")
        #expect(m.spawnDepth == 2)
    }

    @Test("極簡形狀（只有四個欄位）也要能解析")
    func minimalShapeParses() throws {
        let m = try meta("agent-minimal")
        #expect(m.agentType == "Explore")
        #expect(m.requestShape == nil)
    }

    @Test("沒見過的 key 不得讓解析失敗 —— 這個 schema 沒有官方契約")
    func unknownKeysAreHarmless() throws {
        #expect(try meta("agent-minimal").description == "Read the docs")
    }

    @Test("workflow agent 認得出來，而且它沒有任何 parent 欄位")
    func workflowAgentHasNoParentFields() throws {
        let base = try Fixture.projectsRoot().appendingPathComponent(
            "-tmp-fixture-project/\(Fixture.agentSessionId)/subagents/workflows/wf_fixture01")
        let m = try #require(reader.read(base.appendingPathComponent("agent-w1.meta.json")))
        #expect(m.isWorkflowAgent == true)
        #expect(m.workflowPhase == "Build")
        #expect(m.toolUseId == nil)
        #expect(m.parentAgentId == nil)
    }

    @Test("不是 meta.json 的檔案回傳 nil")
    func nonMetaFileYieldsNil() throws {
        let u = try Fixture.projectsRoot().appendingPathComponent(
            "-tmp-fixture-project/\(Fixture.agentSessionId)/subagents/agent-plain1.jsonl")
        #expect(reader.read(u) == nil)
    }
}
